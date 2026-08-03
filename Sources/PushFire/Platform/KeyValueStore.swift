import Foundation

/// Persistent key-value storage for SDK state.
protocol KeyValueStore: Sendable {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool?
    func setString(_ value: String, forKey key: String)
    func setBool(_ value: Bool, forKey key: String)
    func remove(forKey key: String)
}

/// Storage keys. The names match the Flutter SDK's, but not the keys it actually
/// writes — see `UserDefaultsStore.flutterPrefix`.
enum StorageKey {
    static let deviceId = "pushfire_device_id"
    static let fcmToken = "pushfire_fcm_token"
    static let lastPermissionStatus = "pushfire_last_permission_status"
    static let notificationPreference = "pushfire_notification_preference"
    static let subscriberId = "pushfire_subscriber_id"
    static let subscriberData = "pushfire_subscriber_data"
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

    /// The Flutter SDK stores its state through `shared_preferences`, which prefixes
    /// every key it writes with `flutter.` — the prefix is hardcoded in
    /// `shared_preferences_legacy.dart`. So an app that shipped the Flutter SDK holds
    /// its device id under `flutter.pushfire_device_id`, not `pushfire_device_id`.
    ///
    /// Without a fallback, swapping the Flutter SDK for this one reads nil, takes the
    /// new-device branch, and registers a *second* device row for the same physical
    /// device — leaving the first orphaned server-side while it still holds a live FCM
    /// token and can still receive pushes.
    ///
    /// Reads fall back to the prefixed key and adopt the value under the unprefixed
    /// one. The prefixed key is left in place: the host app may still be running
    /// Flutter code that expects to find it.
    private static let flutterPrefix = "flutter."

    func string(forKey key: String) -> String? {
        if let value = defaults.string(forKey: key) {
            return value
        }
        guard let inherited = defaults.string(forKey: Self.flutterPrefix + key) else {
            return nil
        }
        defaults.set(inherited, forKey: key)
        return inherited
    }

    func bool(forKey key: String) -> Bool? {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        guard let inherited = defaults.object(forKey: Self.flutterPrefix + key) as? Bool else {
            return nil
        }
        defaults.set(inherited, forKey: key)
        return inherited
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
        // Both, or the next read would inherit the Flutter value again and resurrect
        // state that `clearDeviceData()` and logout are supposed to have erased.
        defaults.removeObject(forKey: Self.flutterPrefix + key)
    }
}
