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

    /// Configures the SDK and registers this device.
    ///
    /// Call once, before using `shared`. Calling it again while already configured is a
    /// no-op.
    ///
    /// - Parameters:
    ///   - configuration: API key and options.
    ///   - authProvider: Optional. Supply `FirebaseAuthProvider` or `SupabaseAuthProvider`
    ///     to log subscribers in and out automatically from your auth state.
    public static func configure(
        _ configuration: PushFireConfiguration,
        authProvider: (any AuthProvider)? = nil
    ) async throws {
        try configuration.validate()

        let core = PushFireCore.live(config: configuration, authProvider: authProvider)

        // Start before publishing. Publishing first leaves a window where a concurrent
        // `shutdown()` clears the instance while `start()` is still running, stranding a
        // core with live background observers that nothing can reach or stop.
        await core.start()

        guard adopt(PushFire(core: core)) else {
            // Someone else configured while we were starting. Stop the core we started
            // rather than leaking its observers.
            await core.shutdown()
            return
        }
    }

    /// The configured SDK instance.
    ///
    /// - Throws: `PushFireError.notInitialized` if `configure` has not completed.
    public static var shared: PushFire {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            guard let instance else { throw PushFireError.notInitialized }
            return instance
        }
    }

    /// Whether `configure` has completed.
    public static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return instance != nil
    }

    /// Stops the SDK's observers and releases the instance.
    public static func shutdown() async {
        let existing = lock.withLock {
            let existing = instance
            instance = nil
            return existing
        }

        await existing?.core.shutdown()
    }

    /// Adopts `candidate` as the instance. Returns false if one already exists.
    private static func adopt(_ candidate: PushFire) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard instance == nil else { return false }
        instance = candidate
        return true
    }

    /// Installs a core built with test doubles.
    ///
    /// Deliberately does not shut down an existing instance first, so tests can verify
    /// that configuring twice is a no-op. Call `shutdown()` explicitly to reset.
    static func configureForTesting(core: PushFireCore) async {
        await core.start()
        if !adopt(PushFire(core: core)) {
            await core.shutdown()
        }
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
