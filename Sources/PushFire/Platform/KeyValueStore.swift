import Foundation

/// Persistent key-value storage for SDK state.
protocol KeyValueStore: Sendable {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool?
    func setString(_ value: String, forKey key: String)
    func setBool(_ value: Bool, forKey key: String)
    func remove(forKey key: String)
}

/// Storage keys, matching the Flutter SDK so behaviour is directly comparable.
enum StorageKey {
    static let deviceId = "pushfire_device_id"
    static let fcmToken = "pushfire_fcm_token"
    static let lastPermissionStatus = "pushfire_last_permission_status"
    static let notificationPreference = "pushfire_notification_preference"
    static let subscriberId = "pushfire_subscriber_id"
    static let subscriberData = "pushfire_subscriber_data"

    static let all = [
        deviceId, fcmToken, lastPermissionStatus,
        notificationPreference, subscriberId, subscriberData,
    ]
}

/// The live store, backed by `UserDefaults`.
struct UserDefaultsStore: KeyValueStore {
    // `UserDefaults` is thread-safe by contract (Apple's documentation guarantees
    // this) but is not marked `Sendable` by the SDK. `nonisolated(unsafe)` opts this
    // stored property out of the compiler's Sendable check without weakening the
    // struct's own `Sendable` conformance, which `KeyValueStore` requires.
    private nonisolated(unsafe) let defaults: UserDefaults

    init(suiteName: String?) {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
