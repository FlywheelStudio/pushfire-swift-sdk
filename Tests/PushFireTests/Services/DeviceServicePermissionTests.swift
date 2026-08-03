import Foundation
import Testing

@testable import PushFire

private func makeService(
    transport: FakeTransport,
    store: FakeStore,
    permissions: FakePermissionProvider,
    tokens: FakeTokenProvider = FakeTokenProvider()
) -> DeviceService {
    let config = PushFireConfiguration(apiKey: "k", requestNotificationPermission: false)
    return DeviceService(
        apiClient: APIClient(
            config: config,
            transport: transport,
            logger: PushFireLogger(enabled: false)
        ),
        config: config,
        store: store,
        deviceInfo: FakeDeviceInfoProvider(),
        permissions: permissions,
        tokens: tokens,
        logger: PushFireLogger(enabled: false),
        apnsPollInterval: .milliseconds(1),
        apnsPollAttempts: 2
    )
}

private func registeredStore(
    lastPermission: Bool,
    preference: Bool?
) -> FakeStore {
    var values: [String: Any] = [
        StorageKey.deviceId: "dev_1",
        StorageKey.fcmToken: "fcm-token",
        StorageKey.lastPermissionStatus: lastPermission,
    ]
    if let preference {
        values[StorageKey.notificationPreference] = preference
    }
    return FakeStore(values)
}

// MARK: - The foreground sync matrix

@Test func syncPersistsCurrentWhenNoLastStatus() async throws {
    let transport = FakeTransport(responses: [])
    let store = FakeStore([StorageKey.deviceId: "dev_1", StorageKey.fcmToken: "fcm-token"])
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result == nil)
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == true)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func syncDoesNothingWhenUnchanged() async throws {
    let transport = FakeTransport(responses: [])
    let store = registeredStore(lastPermission: true, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result == nil)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func syncPatchesFalseWhenPermissionRevoked() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let store = registeredStore(lastPermission: true, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .denied)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result != nil)
    let data = try await transport.requestData(at: 0)
    #expect(data["pushNotificationEnabled"] as? Bool == false)
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == false)
}

@Test func syncRestoresWhenRegrantedAndPreferenceOn() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let store = registeredStore(lastPermission: false, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result != nil)
    let data = try await transport.requestData(at: 0)
    #expect(data["pushNotificationEnabled"] as? Bool == true)
}

@Test func syncRestoresWhenRegrantedAndPreferenceUnset() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let store = registeredStore(lastPermission: false, preference: nil)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result != nil)
    let recorded = await transport.recorded
    #expect(recorded.count == 1)
}

@Test func syncLeavesServerAloneWhenRegrantedButPreferenceOff() async throws {
    let transport = FakeTransport(responses: [])
    let store = registeredStore(lastPermission: false, preference: false)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result == nil)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
    // The OS change is acknowledged so it is not re-detected on every resume.
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == true)
}

@Test func syncDoesNotAdvanceStatusWhenServerCallFails() async throws {
    // Persisting the new status before a successful sync would make registerDevice see
    // "no change" and skip the update, and would suppress the retry on next resume.
    let transport = FakeTransport(response: .failure(500, #"{"message":"nope"}"#))
    let store = registeredStore(lastPermission: true, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .denied)
    )

    let result = await service.checkAndHandlePermissionStatusChange()

    #expect(result == nil)
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == true)
}

// MARK: - setNotificationEnabled

@Test func setEnabledRefusesWhenOSPermissionDenied() async throws {
    let transport = FakeTransport(responses: [])
    let store = registeredStore(lastPermission: false, preference: false)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .denied)
    )

    let result = try await service.setNotificationEnabled(true)

    #expect(result == .systemPermissionDenied)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func setEnabledShortCircuitsWhenPreferenceMatches() async throws {
    let transport = FakeTransport(responses: [])
    let store = registeredStore(lastPermission: true, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = try await service.setNotificationEnabled(true)

    #expect(result == .success)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func setDisabledPatchesAndPersists() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let store = registeredStore(lastPermission: true, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    let result = try await service.setNotificationEnabled(false)

    #expect(result == .success)
    let data = try await transport.requestData(at: 0)
    #expect(data["id"] as? String == "dev_1")
    #expect(data["pushNotificationEnabled"] as? Bool == false)
    #expect(store.bool(forKey: StorageKey.notificationPreference) == false)
}

@Test func setEnabledDoesNotPersistWhenServerRejects() async throws {
    // Divergence 4 from the spec: the Dart saves the preference before the PATCH, so a
    // failed call leaves local and remote disagreeing.
    let transport = FakeTransport(response: .failure(500, #"{"message":"nope"}"#))
    let store = registeredStore(lastPermission: true, preference: true)
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    await #expect(throws: PushFireError.self) {
        _ = try await service.setNotificationEnabled(false)
    }

    #expect(store.bool(forKey: StorageKey.notificationPreference) == true)
}

@Test func setEnabledThrowsWhenNoDeviceRegistered() async throws {
    let transport = FakeTransport(responses: [])
    let store = FakeStore()
    let service = makeService(
        transport: transport,
        store: store,
        permissions: FakePermissionProvider(status: .authorized)
    )

    await #expect(throws: PushFireError.self) {
        _ = try await service.setNotificationEnabled(false)
    }
}

// MARK: - Status and manual request

@Test func statusDefaultsPreferenceToTrue() async throws {
    let service = makeService(
        transport: FakeTransport(responses: []),
        store: FakeStore(),
        permissions: FakePermissionProvider(status: .provisional)
    )

    let status = await service.notificationStatus()

    #expect(status.isPermissionGranted == true)
    #expect(status.isEnabled == true)
}

@Test func statusReportsDeniedPermission() async throws {
    let service = makeService(
        transport: FakeTransport(responses: []),
        store: FakeStore([StorageKey.notificationPreference: false]),
        permissions: FakePermissionProvider(status: .denied)
    )

    let status = await service.notificationStatus()

    #expect(status.isPermissionGranted == false)
    #expect(status.isEnabled == false)
}

@Test func manualRequestRegistersDeviceWhenGranted() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let permissions = FakePermissionProvider(status: .notDetermined, requestResult: .authorized)
    let service = makeService(transport: transport, store: FakeStore(), permissions: permissions)

    let result = try await service.requestNotificationPermission()

    #expect(result.granted == true)
    #expect(result.device?.id == "dev_1")
    let recorded = await transport.recorded
    #expect(recorded.count == 1)
    #expect(recorded[0].url?.lastPathComponent == "register-device")
}

@Test func manualRequestDoesNotRegisterWhenDenied() async throws {
    let transport = FakeTransport(responses: [])
    let permissions = FakePermissionProvider(status: .notDetermined, requestResult: .denied)
    let service = makeService(transport: transport, store: FakeStore(), permissions: permissions)

    let result = try await service.requestNotificationPermission()

    #expect(result.granted == false)
    #expect(result.device == nil)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func openSettingsDelegatesToProvider() async throws {
    let permissions = FakePermissionProvider(status: .denied)
    let service = makeService(
        transport: FakeTransport(responses: []),
        store: FakeStore(),
        permissions: permissions
    )

    let opened = await service.openNotificationSettings()

    #expect(opened == true)
    #expect(permissions.openedSettings == 1)
}
