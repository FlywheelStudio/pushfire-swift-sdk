import Foundation

/// Holds the SDK's services and state, and owns the background observers.
actor PushFireCore {
    let config: PushFireConfiguration

    private let deviceService: DeviceService
    private let subscriberService: SubscriberService
    private let tagService: TagService
    private let workflowService: WorkflowService
    private let broadcaster = EventBroadcaster()
    private let tokens: any PushTokenProvider
    private let lifecycle: any AppLifecycleObserver
    private let authProvider: (any AuthProvider)?
    private let logger: PushFireLogger
    /// Retained so `shutdown()` can release it. A `URLSession` outlives the objects that
    /// use it until explicitly invalidated.
    private let transport: any HTTPTransport

    private var device: Device?
    private var observers: [Task<Void, Never>] = []
    /// The in-flight permission check. Concurrent callers await this one rather than
    /// starting a second check — the Swift equivalent of the Dart's `_isCheckingPermission`
    /// flag, without the race.
    private var permissionCheck: Task<Device?, Never>?

    init(
        config: PushFireConfiguration,
        transport: any HTTPTransport,
        store: any KeyValueStore,
        deviceInfo: any DeviceInfoProvider,
        permissions: any NotificationPermissionProvider,
        tokens: any PushTokenProvider,
        lifecycle: any AppLifecycleObserver,
        authProvider: (any AuthProvider)?,
        apnsPollInterval: PollInterval = .milliseconds(500),
        apnsPollAttempts: Int = 10
    ) {
        let logger = PushFireLogger(enabled: config.enableLogging)
        let apiClient = APIClient(config: config, transport: transport, logger: logger)

        self.config = config
        self.logger = logger
        self.tokens = tokens
        self.lifecycle = lifecycle
        self.authProvider = authProvider
        self.transport = transport

        self.deviceService = DeviceService(
            apiClient: apiClient,
            config: config,
            store: store,
            deviceInfo: deviceInfo,
            permissions: permissions,
            tokens: tokens,
            logger: logger,
            apnsPollInterval: apnsPollInterval,
            apnsPollAttempts: apnsPollAttempts
        )
        self.subscriberService = SubscriberService(
            apiClient: apiClient,
            deviceService: deviceService,
            store: store,
            logger: logger
        )
        self.tagService = TagService(
            apiClient: apiClient,
            subscriberService: subscriberService,
            logger: logger
        )
        self.workflowService = WorkflowService(apiClient: apiClient, logger: logger)
    }

    /// Builds a core wired to the live platform implementations.
    ///
    /// A static factory rather than a delegating initialiser: `self.init` delegation is
    /// not available in an actor.
    static func live(
        config: PushFireConfiguration,
        authProvider: (any AuthProvider)?,
        pushTokenProvider: (any PushTokenProvider)? = nil
    ) -> PushFireCore {
        PushFireCore(
            config: config,
            transport: URLSessionTransport(timeout: config.timeout),
            store: UserDefaultsStore(suiteName: config.userDefaultsSuiteName),
            deviceInfo: SystemDeviceInfoProvider(),
            permissions: UserNotificationsPermissionProvider(),
            tokens: pushTokenProvider ?? FirebasePushTokenProvider(),
            lifecycle: NotificationCenterLifecycleObserver(),
            authProvider: authProvider
        )
    }

    // MARK: - Lifecycle

    /// Registers the device and starts the background observers.
    func start() async {
        await autoRegisterDevice()
        observeTokenRefresh()
        observeForeground()
        observeAuth()
    }

    /// Cancels the observers and closes the event stream.
    func shutdown() async {
        for observer in observers {
            observer.cancel()
        }
        observers.removeAll()
        permissionCheck?.cancel()
        permissionCheck = nil
        await broadcaster.finish()
        // Cancels in-flight requests and releases the session, mirroring the Flutter
        // SDK's dispose() closing its http client.
        transport.close()
        logger.info("SDK shut down")
    }

    private func autoRegisterDevice() async {
        do {
            if let registered = try await deviceService.registerDevice() {
                device = registered
                await broadcaster.emit(.deviceRegistered(registered))
            }
        } catch {
            // Registration failing must not stop the SDK from working; the token-refresh
            // and foreground observers will retry.
            logger.warning("Device auto-registration failed", error)
        }
    }

    private func observeTokenRefresh() {
        let stream = tokens.tokenRefreshes
        observers.append(
            Task { [weak self] in
                for await token in stream {
                    guard let self else { return }
                    await self.handleTokenRefresh(token)
                }
            }
        )
    }

    private func handleTokenRefresh(_ token: String) async {
        logger.info("Push token refreshed")
        // Coalesced by the same permissionCheck guard as the foreground observer, but
        // deliberately does not emit: the registerDevice() below already emits
        // .deviceRegistered for this refresh. Emitting here too would produce two
        // events for one logical change whenever a token rotation coincides with a
        // permission change. The Flutter SDK emits exactly one.
        _ = await coalescedPermissionCheck()
        do {
            if let registered = try await deviceService.registerDevice() {
                device = registered
                await broadcaster.emit(.deviceRegistered(registered))
            }
            await broadcaster.emit(.pushTokenRefreshed(token))
        } catch {
            logger.warning("Could not update the device with the new push token", error)
        }
    }

    private func observeForeground() {
        let stream = lifecycle.didBecomeActive
        observers.append(
            Task { [weak self] in
                for await _ in stream {
                    guard let self else { return }
                    _ = await self.syncNotificationPermission()
                }
            }
        )
    }

    private func observeAuth() {
        guard let authProvider else { return }
        let stream = authProvider.events
        observers.append(
            Task { [weak self] in
                for await event in stream {
                    guard let self else { return }
                    await self.handleAuthEvent(event)
                }
            }
        )
    }

    private func handleAuthEvent(_ event: AuthEvent) async {
        switch event {
        case .signedIn(let user):
            let current = await subscriberService.currentSubscriber()
            if current?.externalId == user.id {
                logger.info("Already logged in as \(user.id) - skipping auto-login")
                return
            }
            do {
                _ = try await login(
                    externalId: user.id,
                    name: user.name,
                    email: user.email,
                    phone: user.phone,
                    metadata: nil
                )
            } catch {
                logger.warning("Auto-login failed", error)
            }
        case .signedOut:
            do {
                try await logout()
            } catch {
                logger.warning("Auto-logout failed", error)
            }
        }
    }

    // MARK: - Events and state

    func eventStream() async -> AsyncStream<PushFireEvent> {
        await broadcaster.stream()
    }

    func currentDevice() -> Device? { device }

    func currentSubscriber() async -> Subscriber? {
        await subscriberService.currentSubscriber()
    }

    func isSubscriberLoggedIn() async -> Bool {
        await subscriberService.isLoggedIn()
    }

    func deviceId() async -> String? { await deviceService.deviceId() }

    func subscriberId() async -> String? { await subscriberService.subscriberId() }

    // MARK: - Subscribers

    @discardableResult
    func login(
        externalId: String,
        name: String?,
        email: String?,
        phone: String?,
        metadata: [String: JSONValue]?
    ) async throws -> Subscriber {
        let subscriber = try await subscriberService.login(
            externalId: externalId,
            name: name,
            email: email,
            phone: phone,
            metadata: metadata
        )
        await broadcaster.emit(.subscriberLoggedIn(subscriber))
        return subscriber
    }

    @discardableResult
    func updateSubscriber(
        name: String?,
        email: String?,
        phone: String?,
        metadata: [String: JSONValue]?
    ) async throws -> Subscriber {
        try await subscriberService.updateSubscriber(
            name: name,
            email: email,
            phone: phone,
            metadata: metadata
        )
    }

    func logout() async throws {
        do {
            try await subscriberService.logout()
        } catch {
            // The service clears local state even when the server call fails, so mirror
            // that cleared session by emitting the event regardless. The error still
            // propagates.
            await broadcaster.emit(.subscriberLoggedOut)
            throw error
        }
        await broadcaster.emit(.subscriberLoggedOut)
    }

    // MARK: - Tags

    @discardableResult
    func addTag(_ tagId: String, value: String) async throws -> SubscriberTag {
        try await tagService.addTag(tagId, value: value)
    }

    @discardableResult
    func updateTag(_ tagId: String, value: String) async throws -> SubscriberTag {
        try await tagService.updateTag(tagId, value: value)
    }

    func removeTag(_ tagId: String) async throws {
        try await tagService.removeTag(tagId)
    }

    func addTags(_ tags: [(String, String)]) async throws -> BulkTagResult {
        try await tagService.addTags(tags)
    }

    func updateTags(_ tags: [(String, String)]) async throws -> BulkTagResult {
        try await tagService.updateTags(tags)
    }

    func removeTags(_ tagIds: [String]) async throws -> BulkTagResult {
        try await tagService.removeTags(tagIds)
    }

    // MARK: - Workflows

    @discardableResult
    func runWorkflow(
        _ workflowId: String,
        target: WorkflowRunTarget,
        at date: Date?
    ) async throws -> WorkflowExecutionResponse {
        try await workflowService.run(workflowId, target: target, at: date)
    }

    @discardableResult
    func createWorkflowExecution(
        _ request: WorkflowExecutionRequest
    ) async throws -> WorkflowExecutionResponse {
        try await workflowService.createWorkflowExecution(request)
    }

    // MARK: - Notifications

    func requestNotificationPermission() async throws -> Bool {
        let result = try await deviceService.requestNotificationPermission()
        if let registered = result.device {
            device = registered
            await broadcaster.emit(.deviceRegistered(registered))
        }
        return result.granted
    }

    func notificationStatus() async -> NotificationStatus {
        await deviceService.notificationStatus()
    }

    func setNotificationEnabled(_ enabled: Bool) async throws -> SetNotificationResult {
        let result = try await deviceService.setNotificationEnabled(enabled)
        if result == .success, let current = device {
            let updated = current.with(pushNotificationEnabled: enabled)
            device = updated
            await broadcaster.emit(.deviceRegistered(updated))
        }
        return result
    }

    /// Runs the permission check, coalescing concurrent callers, and updates `device`.
    ///
    /// Returns the refreshed device only to the caller that owns the check, so one
    /// permission change produces one state update no matter how many callers are
    /// waiting. Emits nothing — the caller decides whether this change warrants an
    /// event.
    private func coalescedPermissionCheck() async -> Device? {
        if let existing = permissionCheck {
            _ = await existing.value
            return nil
        }

        let task = Task { [deviceService] in
            await deviceService.checkAndHandlePermissionStatusChange()
        }
        permissionCheck = task
        let updated = await task.value
        permissionCheck = nil

        if let updated {
            device = updated
        }
        return updated
    }

    /// Re-checks the OS permission and syncs any change, then reports the current status.
    @discardableResult
    func syncNotificationPermission() async -> NotificationStatus {
        if let updated = await coalescedPermissionCheck() {
            await broadcaster.emit(.deviceRegistered(updated))
        }
        return await deviceService.notificationStatus()
    }

    func openNotificationSettings() async -> Bool {
        await deviceService.openNotificationSettings()
    }

    // MARK: - Reset

    /// Logs out and clears all local state.
    func reset() async throws {
        logger.info("Resetting SDK")
        if await subscriberService.isLoggedIn() {
            try? await logout()
        }
        // Unconditional: a stored subscriber with a nil id would survive the
        // `isLoggedIn()`-gated logout above, leaving data behind after a reset that
        // claims to clear all local state.
        await subscriberService.clearLocalData()
        await deviceService.clearDeviceData()
        device = nil
        logger.info("SDK reset completed")
    }
}
