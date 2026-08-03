import Foundation

/// The PushFire SDK.
///
/// Configure once at launch, then use `PushFire.shared` for everything else.
///
/// ```swift
/// try await PushFire.configure(PushFireConfiguration(apiKey: "your-api-key"))
/// try await PushFire.shared.login(externalId: "user_123", name: "Jane")
/// ```
public final class PushFire: Sendable {
    /// This SDK's version, matching the released git tag.
    public static let sdkVersion = "0.1.0"

    private let core: PushFireCore

    private init(core: PushFireCore) {
        self.core = core
    }

    // MARK: - Singleton

    private static let lock = NSLock()
    nonisolated(unsafe) private static var instance: PushFire?
    /// The in-flight (or completed) configuration. Concurrent `configure()` callers
    /// await this same task rather than each building and starting their own core
    /// against the same `UserDefaults` suite — the same coalescing pattern
    /// `DeviceService.registerDevice()` uses for registration. A sequential second
    /// `configure()` call sees this already set and returns the first instance without
    /// starting a second core, which also avoids a wasted device registration.
    nonisolated(unsafe) private static var configuration: Task<PushFire, any Error>?

    /// Configures the SDK and registers this device.
    ///
    /// Call once, before using `shared`. Calling it again while already configured is a
    /// no-op.
    ///
    /// - Parameters:
    ///   - configuration: API key and options.
    ///   - authProvider: Optional. Supply `FirebaseAuthProvider` or `SupabaseAuthProvider`
    ///     to log subscribers in and out automatically from your auth state.
    ///   - pushTokenProvider: Optional. Supply your own push-token acquisition instead of
    ///     the default FirebaseMessaging-backed implementation.
    public static func configure(
        _ configuration: PushFireConfiguration,
        authProvider: (any AuthProvider)? = nil,
        pushTokenProvider: (any PushTokenProvider)? = nil
    ) async throws {
        try configuration.validate()

        let task = lock.withLock { () -> Task<PushFire, any Error> in
            if let existing = Self.configuration {
                return existing
            }
            let newTask = Task<PushFire, any Error> {
                let core = PushFireCore.live(
                    config: configuration,
                    authProvider: authProvider,
                    pushTokenProvider: pushTokenProvider
                )
                await core.start()
                let pushFire = PushFire(core: core)
                lock.withLock { Self.instance = pushFire }
                return pushFire
            }
            Self.configuration = newTask
            return newTask
        }

        _ = try await task.value
    }

    /// The configured SDK instance.
    ///
    /// - Throws: `PushFireError.notInitialized` if `configure` has not completed.
    public static var shared: PushFire {
        get throws {
            guard let instance = lock.withLock({ Self.instance }) else {
                throw PushFireError.notInitialized
            }
            return instance
        }
    }

    /// Whether `configure` has completed.
    public static var isConfigured: Bool {
        lock.withLock { Self.instance != nil }
    }

    /// Stops the SDK's observers and releases the instance.
    ///
    /// `configure(_:authProvider:pushTokenProvider:)` and `shutdown()` must not be called
    /// concurrently. Sequential use is safe. Calling them concurrently can leave the SDK
    /// reporting itself configured while its background observers are stopped.
    public static func shutdown() async {
        let existing = lock.withLock { () -> Task<PushFire, any Error>? in
            let existing = Self.configuration
            Self.configuration = nil
            Self.instance = nil
            return existing
        }

        guard let existing else { return }
        if let pushFire = try? await existing.value {
            await pushFire.core.shutdown()
        }
    }

    /// Installs a core built with test doubles.
    ///
    /// Deliberately does not shut down an existing instance first, so tests can verify
    /// that configuring twice is a no-op. Call `shutdown()` explicitly to reset.
    static func configureForTesting(core: PushFireCore) async {
        let (task, isWinner) = lock.withLock { () -> (Task<PushFire, any Error>, Bool) in
            if let existing = Self.configuration {
                return (existing, false)
            }
            let newTask = Task<PushFire, any Error> {
                await core.start()
                let pushFire = PushFire(core: core)
                lock.withLock { Self.instance = pushFire }
                return pushFire
            }
            Self.configuration = newTask
            return (newTask, true)
        }

        if !isWinner {
            // Someone else already configured. Shut down the core we were handed
            // instead of leaking it or starting it needlessly.
            await core.shutdown()
        }
        _ = try? await task.value
    }

    // MARK: - Subscribers

    /// Logs a subscriber in, creating them if they do not exist.
    @discardableResult
    public func login(
        externalId: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) async throws -> Subscriber {
        try await core.login(
            externalId: externalId,
            name: name,
            email: email,
            phone: phone,
            metadata: metadata
        )
    }

    /// Updates the logged-in subscriber. `externalId` cannot be changed.
    @discardableResult
    public func updateSubscriber(
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) async throws -> Subscriber {
        try await core.updateSubscriber(
            name: name,
            email: email,
            phone: phone,
            metadata: metadata
        )
    }

    /// Logs the current subscriber out.
    public func logout() async throws {
        try await core.logout()
    }

    /// The logged-in subscriber, read from local storage.
    public var currentSubscriber: Subscriber? {
        get async { await core.currentSubscriber() }
    }

    /// Whether a subscriber is logged in.
    public var isSubscriberLoggedIn: Bool {
        get async { await core.isSubscriberLoggedIn() }
    }

    /// The PushFire subscriber id, if logged in.
    public func subscriberId() async -> String? {
        await core.subscriberId()
    }

    // MARK: - Tags

    @discardableResult
    public func addTag(_ tagId: String, value: String) async throws -> SubscriberTag {
        try await core.addTag(tagId, value: value)
    }

    @discardableResult
    public func updateTag(_ tagId: String, value: String) async throws -> SubscriberTag {
        try await core.updateTag(tagId, value: value)
    }

    public func removeTag(_ tagId: String) async throws {
        try await core.removeTag(tagId)
    }

    /// Adds several tags in order, reporting successes and failures separately.
    @discardableResult
    public func addTags(_ tags: [(String, String)]) async throws -> BulkTagResult {
        try await core.addTags(tags)
    }

    @discardableResult
    public func updateTags(_ tags: [(String, String)]) async throws -> BulkTagResult {
        try await core.updateTags(tags)
    }

    @discardableResult
    public func removeTags(_ tagIds: [String]) async throws -> BulkTagResult {
        try await core.removeTags(tagIds)
    }

    // MARK: - Workflows

    /// Runs a workflow. Pass `at:` to schedule it instead of running immediately.
    @discardableResult
    public func runWorkflow(
        _ workflowId: String,
        for target: WorkflowRunTarget,
        at date: Date? = nil
    ) async throws -> WorkflowExecutionResponse {
        try await core.runWorkflow(workflowId, target: target, at: date)
    }

    // MARK: - Notifications

    /// Prompts for the notification permission. Returns whether it was granted.
    @discardableResult
    public func requestNotificationPermission() async throws -> Bool {
        try await core.requestNotificationPermission()
    }

    /// The OS permission state and the PushFire preference.
    public func notificationStatus() async -> NotificationStatus {
        await core.notificationStatus()
    }

    /// Turns PushFire notifications on or off for this device.
    ///
    /// This is separate from the OS permission: enabling while the OS permission is
    /// denied returns `.systemPermissionDenied` and changes nothing.
    @discardableResult
    public func setNotificationEnabled(_ enabled: Bool) async throws -> SetNotificationResult {
        try await core.setNotificationEnabled(enabled)
    }

    /// Re-checks the OS permission and syncs any change to PushFire.
    ///
    /// The SDK does this automatically when the app returns to the foreground. Call it to
    /// force an immediate sync — typically right after the user comes back from
    /// `openNotificationSettings()`.
    @discardableResult
    public func syncNotificationPermission() async -> NotificationStatus {
        await core.syncNotificationPermission()
    }

    /// Opens this app's page in Settings so the user can grant the permission manually.
    ///
    /// Useful once the permission is permanently denied and
    /// `requestNotificationPermission()` no longer shows a prompt.
    @discardableResult
    public func openNotificationSettings() async -> Bool {
        await core.openNotificationSettings()
    }

    // MARK: - Device and events

    /// The registered device, if registration has completed.
    public var currentDevice: Device? {
        get async { await core.currentDevice() }
    }

    /// The PushFire device id, if registered.
    public func deviceId() async -> String? {
        await core.deviceId()
    }

    /// A stream of SDK events. Each call returns an independent stream.
    public var events: AsyncStream<PushFireEvent> {
        get async { await core.eventStream() }
    }

    /// Logs out and clears all local SDK state.
    public func reset() async throws {
        try await core.reset()
    }
}
