import Foundation
import Testing

@testable import PushFire

@Test func storeDistinguishesUnsetFromFalse() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    #expect(store.bool(forKey: StorageKey.notificationPreference) == nil)

    store.setBool(false, forKey: StorageKey.notificationPreference)
    #expect(store.bool(forKey: StorageKey.notificationPreference) == false)

    store.remove(forKey: StorageKey.notificationPreference)
    #expect(store.bool(forKey: StorageKey.notificationPreference) == nil)
}

@Test func storeRoundTripsStrings() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    store.setString("dev_1", forKey: StorageKey.deviceId)
    #expect(store.string(forKey: StorageKey.deviceId) == "dev_1")
}

@Test func storeFallsBackToStandardDefaultsWithoutASuiteName() {
    // `userDefaultsSuiteName` is optional in the configuration, so the common case is
    // no suite at all — the store still has to read and write somewhere real.
    let key = "pushfire.tests.\(UUID().uuidString)"
    let store = UserDefaultsStore(suiteName: nil)
    defer { UserDefaults.standard.removeObject(forKey: key) }

    store.setString("dev_1", forKey: key)

    #expect(store.string(forKey: key) == "dev_1")
    #expect(UserDefaults.standard.string(forKey: key) == "dev_1")
}

@Test func storeFallsBackToStandardDefaultsWhenTheSuiteCannotBeOpened() throws {
    // `UserDefaults(suiteName:)` returns nil for the global domain. A misconfigured app
    // group must degrade to standard defaults rather than leaving the SDK with no
    // storage at all.
    let unopenable = UserDefaults.globalDomain
    try #require(UserDefaults(suiteName: unopenable) == nil)

    let key = "pushfire.tests.\(UUID().uuidString)"
    let store = UserDefaultsStore(suiteName: unopenable)
    defer { UserDefaults.standard.removeObject(forKey: key) }

    store.setString("dev_1", forKey: key)

    #expect(store.string(forKey: key) == "dev_1")
    #expect(UserDefaults.standard.string(forKey: key) == "dev_1")
}

// MARK: - Migration from the Flutter SDK
//
// `shared_preferences` writes every key with a hardcoded `flutter.` prefix, so an
// app that shipped the Flutter SDK has its state under `flutter.pushfire_device_id`.
// Reading nil there would register a duplicate device row for the same device.

@Test func storeInheritsFlutterWrittenString() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    defaults.set("dev_from_flutter", forKey: "flutter.\(StorageKey.deviceId)")

    #expect(store.string(forKey: StorageKey.deviceId) == "dev_from_flutter")
    // Adopted under the unprefixed key, so later reads no longer depend on the fallback.
    #expect(defaults.string(forKey: StorageKey.deviceId) == "dev_from_flutter")
}

@Test func storeInheritsFlutterWrittenFalseWithoutConfusingItForUnset() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    defaults.set(false, forKey: "flutter.\(StorageKey.notificationPreference)")

    // `false` must survive as `false`, not collapse to nil — the whole permission
    // state machine keys off unset-vs-false.
    #expect(store.bool(forKey: StorageKey.notificationPreference) == false)
    #expect(defaults.object(forKey: StorageKey.notificationPreference) as? Bool == false)
}

@Test func storePrefersItsOwnValueOverTheFlutterOne() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    defaults.set("stale_flutter_value", forKey: "flutter.\(StorageKey.deviceId)")
    store.setString("dev_native", forKey: StorageKey.deviceId)

    #expect(store.string(forKey: StorageKey.deviceId) == "dev_native")
}

@Test func storeRemovalDoesNotResurrectTheFlutterValue() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    defaults.set("dev_from_flutter", forKey: "flutter.\(StorageKey.deviceId)")
    #expect(store.string(forKey: StorageKey.deviceId) == "dev_from_flutter")

    store.remove(forKey: StorageKey.deviceId)

    // clearDeviceData() and logout must actually erase. Falling back to the prefixed
    // key here would hand the caller back state it just deleted.
    #expect(store.string(forKey: StorageKey.deviceId) == nil)
}

@Test func storeReturnsNilWhenNeitherKeyIsSet() {
    let suite = "pushfire.tests.\(UUID().uuidString)"
    let store = UserDefaultsStore(suiteName: suite)
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

    #expect(store.string(forKey: StorageKey.deviceId) == nil)
    #expect(store.bool(forKey: StorageKey.notificationPreference) == nil)
}
