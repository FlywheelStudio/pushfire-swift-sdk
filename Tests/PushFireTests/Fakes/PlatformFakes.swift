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

    init(apns: String? = "apns-token", fcm: String? = "fcm-token") {
        self.apns = apns
        self.fcm = fcm
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

    func apnsToken() async -> String? {
        lock.withLock { apns }
    }

    func fcmToken() async -> String? {
        lock.withLock { fcm }
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
