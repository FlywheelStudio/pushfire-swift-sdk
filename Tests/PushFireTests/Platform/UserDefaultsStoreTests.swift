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
