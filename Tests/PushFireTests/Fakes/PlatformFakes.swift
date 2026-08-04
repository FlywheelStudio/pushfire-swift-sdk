import Foundation

@testable import PushFire

/// In-memory `KeyValueStore`.
final class FakeStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    init(_ initial: [String: Any] = [:]) {
        storage = initial
    }

    func string(forKey key: String) -> String? {
        lock.withLock { storage[key] as? String }
    }

    func bool(forKey key: String) -> Bool? {
        lock.withLock { storage[key] as? Bool }
    }

    func setString(_ value: String, forKey key: String) {
        lock.withLock { storage[key] = value }
    }

    func setBool(_ value: Bool, forKey key: String) {
        lock.withLock { storage[key] = value }
    }

    func remove(forKey key: String) {
        lock.withLock { storage[key] = nil }
    }
}

struct FakeDeviceInfoProvider: DeviceInfoProvider {
    var info = DeviceInfo(
        os: "ios",
        osVersion: "18.0",
        language: "en_US",
        manufacturer: "Apple",
        model: "iPhone",
        appVersion: "1.0.0"
    )

    func deviceInfo() async -> DeviceInfo { info }
}

/// Permission provider with scriptable status and recorded calls.
final class FakePermissionProvider: NotificationPermissionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var status: NotificationAuthorization
    private var requestResult: NotificationAuthorization?

    private(set) var requestedProvisional: [Bool] = []
    private(set) var registeredForRemote = 0
    private(set) var openedSettings = 0
    var settingsOpenResult = true

    init(
        status: NotificationAuthorization = .notDetermined,
        requestResult: NotificationAuthorization? = nil
    ) {
        self.status = status
        self.requestResult = requestResult
    }

    /// Simulates the user changing the permission in Settings.
    func setStatus(_ new: NotificationAuthorization) {
        lock.withLock { status = new }
    }

    func authorizationStatus() async -> NotificationAuthorization {
        lock.withLock { status }
    }

    func requestAuthorization(provisional: Bool) async -> NotificationAuthorization {
        lock.withLock {
            requestedProvisional.append(provisional)
            if let requestResult {
                status = requestResult
            }
            return status
        }
    }

    func registerForRemoteNotifications() async {
        lock.withLock { registeredForRemote += 1 }
    }

    func openSettings() async -> Bool {
        lock.withLock {
            openedSettings += 1
            return settingsOpenResult
        }
    }
}

/// Token provider with scriptable tokens and a manually driven refresh stream.
final class FakeTokenProvider: PushTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var apns: String?
    private var fcm: String?
    private let continuation: AsyncStream<String>.Continuation
    let tokenRefreshes: AsyncStream<String>

    /// Number of `apnsToken()` calls that return nil before the token appears.
    private let apnsAvailableAfterCalls: Int

    init(
        apns: String? = "apns-token",
        fcm: String? = "fcm-token",
        apnsAvailableAfterCalls: Int = 0
    ) {
        self.apns = apns
        self.fcm = fcm
        self.apnsAvailableAfterCalls = apnsAvailableAfterCalls
        var capture: AsyncStream<String>.Continuation!
        self.tokenRefreshes = AsyncStream { capture = $0 }
        self.continuation = capture
    }

    func setFCM(_ token: String?) {
        lock.withLock { fcm = token }
    }

    func setAPNS(_ token: String?) {
        lock.withLock { apns = token }
    }

    /// How many times the APNs token has been asked for. Lets a test pin the poll
    /// window, which has to match the Flutter SDK's.
    ///
    /// Read under the same lock as the value it counts: the poll loop runs on the
    /// cooperative pool while the test reads from another task, and this type is
    /// `@unchecked Sendable`, so an unsynchronised read here is a data race the compiler
    /// will not catch.
    var apnsCallCount: Int { lock.withLock { calls } }
    private var calls = 0

    func apnsToken() async -> String? {
        lock.withLock {
            calls += 1
            // Models Apple delivering the token a moment after registration, without a
            // test needing to race a background task against the poll loop.
            return calls > apnsAvailableAfterCalls ? apns : nil
        }
    }

    /// Proves the FCM fetch is skipped when no APNs token arrived.
    var fcmCallCount: Int { lock.withLock { fcmCalls } }
    private var fcmCalls = 0

    func fcmToken() async -> String? {
        lock.withLock {
            fcmCalls += 1
            return fcm
        }
    }

    /// Simulates FCM rotating the token.
    func emitRefresh(_ token: String) {
        continuation.yield(token)
    }
}

/// Lifecycle observer driven manually from tests.
final class FakeLifecycleObserver: AppLifecycleObserver, @unchecked Sendable {
    private let continuation: AsyncStream<Void>.Continuation
    let didBecomeActive: AsyncStream<Void>

    init() {
        var capture: AsyncStream<Void>.Continuation!
        self.didBecomeActive = AsyncStream { capture = $0 }
        self.continuation = capture
    }

    /// Simulates the app returning to the foreground.
    func emitDidBecomeActive() {
        continuation.yield(())
    }
}
