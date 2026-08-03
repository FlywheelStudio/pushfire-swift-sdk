import Foundation
import Testing

@testable import PushFire

private func makeService(
    transport: FakeTransport,
    store: FakeStore = FakeStore(),
    permissions: FakePermissionProvider = FakePermissionProvider(status: .authorized),
    tokens: FakeTokenProvider = FakeTokenProvider(),
    config: PushFireConfiguration = PushFireConfiguration(
        apiKey: "k",
        requestNotificationPermission: false
    )
) -> DeviceService {
    DeviceService(
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

@Test func registersNewDeviceAndPersistsState() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let store = FakeStore()
    let service = makeService(transport: transport, store: store)

    let device = try await service.registerDevice()

    #expect(device?.id == "dev_1")

    let recorded = await transport.recorded
    #expect(recorded.count == 1)
    #expect(recorded[0].url?.lastPathComponent == "register-device")

    let data = try await transport.requestData(at: 0)
    #expect(data["fcmToken"] as? String == "fcm-token")
    #expect(data["os"] as? String == "ios")
    #expect(data["manufacturer"] as? String == "Apple")
    #expect(data["pushNotificationEnabled"] as? Bool == true)
    #expect(data["id"] == nil)

    #expect(store.string(forKey: StorageKey.deviceId) == "dev_1")
    #expect(store.string(forKey: StorageKey.fcmToken) == "fcm-token")
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == true)
    #expect(store.bool(forKey: StorageKey.notificationPreference) == true)
}

@Test func skipsServerCallWhenNothingChanged() async throws {
    let transport = FakeTransport(responses: [])
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.fcmToken: "fcm-token",
        StorageKey.lastPermissionStatus: true,
        StorageKey.notificationPreference: true,
    ])
    let service = makeService(transport: transport, store: store)

    let device = try await service.registerDevice()

    #expect(device?.id == "dev_1")
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func patchesWhenTokenChanged() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.fcmToken: "old-token",
        StorageKey.lastPermissionStatus: true,
        StorageKey.notificationPreference: true,
    ])
    let service = makeService(transport: transport, store: store)

    _ = try await service.registerDevice()

    let recorded = await transport.recorded
    #expect(recorded.count == 1)
    #expect(recorded[0].url?.lastPathComponent == "update-device")
    #expect(recorded[0].httpMethod == "PATCH")

    let data = try await transport.requestData(at: 0)
    #expect(data["id"] as? String == "dev_1")
    #expect(data["fcmToken"] as? String == "fcm-token")
    #expect(store.string(forKey: StorageKey.fcmToken) == "fcm-token")
}

@Test func patchesWhenOSPermissionChanged() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.fcmToken: "fcm-token",
        StorageKey.lastPermissionStatus: false,
        StorageKey.notificationPreference: true,
    ])
    let service = makeService(transport: transport, store: store)

    _ = try await service.registerDevice()

    let recorded = await transport.recorded
    #expect(recorded.count == 1)
    #expect(recorded[0].url?.lastPathComponent == "update-device")

    let data = try await transport.requestData(at: 0)
    #expect(data["pushNotificationEnabled"] as? Bool == true)
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == true)
}

@Test func doesNotPatchWhenOnlyPreferenceIsOff() async throws {
    // Divergence 3 from the spec. The Dart compares the saved *raw* OS permission
    // against the *effective* value, so this case PATCHes on every single launch.
    // Comparing like for like, nothing has changed, so nothing is sent.
    let transport = FakeTransport(responses: [])
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.fcmToken: "fcm-token",
        StorageKey.lastPermissionStatus: true,
        StorageKey.notificationPreference: false,
    ])
    let service = makeService(transport: transport, store: store)

    let device = try await service.registerDevice()

    #expect(device?.pushNotificationEnabled == false)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func returnsNilWhenNoFCMToken() async throws {
    let transport = FakeTransport(responses: [])
    let tokens = FakeTokenProvider(apns: "apns", fcm: nil)
    let service = makeService(transport: transport, tokens: tokens)

    let device = try await service.registerDevice()

    #expect(device == nil)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func returnsNilWhenAPNSTokenNeverArrives() async throws {
    let transport = FakeTransport(responses: [])
    let tokens = FakeTokenProvider(apns: nil, fcm: "fcm-token")
    let service = makeService(transport: transport, tokens: tokens)

    let device = try await service.registerDevice()

    #expect(device == nil)
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func requestsPermissionOnlyWhenNotDetermined() async throws {
    let permissions = FakePermissionProvider(status: .notDetermined, requestResult: .authorized)
    let service = makeService(
        transport: FakeTransport(response: .ok(#"{"id":"dev_1"}"#)),
        permissions: permissions,
        config: PushFireConfiguration(apiKey: "k", requestNotificationPermission: true)
    )

    _ = try await service.registerDevice()

    #expect(permissions.requestedProvisional == [false])
}

@Test func doesNotRequestPermissionWhenAlreadyDenied() async throws {
    let permissions = FakePermissionProvider(status: .denied)
    let service = makeService(
        transport: FakeTransport(response: .ok(#"{"id":"dev_1"}"#)),
        permissions: permissions,
        config: PushFireConfiguration(apiKey: "k", requestNotificationPermission: true)
    )

    _ = try await service.registerDevice()

    #expect(permissions.requestedProvisional.isEmpty)
}

@Test func requestsProvisionalAuthorizationWhenRegisteringWithoutPrompt() async throws {
    let permissions = FakePermissionProvider(status: .notDetermined, requestResult: .provisional)
    let service = makeService(
        transport: FakeTransport(response: .ok(#"{"id":"dev_1"}"#)),
        permissions: permissions,
        config: PushFireConfiguration(
            apiKey: "k",
            requestNotificationPermission: false,
            registerWithoutPrompt: true
        )
    )

    _ = try await service.registerDevice()

    #expect(permissions.requestedProvisional == [true])
}

@Test func throwsWhenRegistrationReturnsNoID() async throws {
    let service = makeService(transport: FakeTransport(response: .ok(#"{"ok":true}"#)))

    await #expect(throws: PushFireError.self) {
        _ = try await service.registerDevice()
    }
}

@Test func concurrentRegisterDeviceCoalescesIntoOneRequest() async throws {
    // Only one response is queued: if the in-flight guard failed to coalesce, the
    // second concurrent call would consume a second request and throw
    // "FakeTransport ran out of queued responses" rather than returning dev_1.
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let store = FakeStore()
    let service = makeService(transport: transport, store: store)

    async let first = service.registerDevice()
    async let second = service.registerDevice()

    let (firstDevice, secondDevice) = try await (first, second)

    #expect(firstDevice?.id == "dev_1")
    #expect(secondDevice?.id == "dev_1")

    let recorded = await transport.recorded
    #expect(recorded.count == 1)
    #expect(recorded[0].url?.lastPathComponent == "register-device")
}

@Test func clearDeviceDataRemovesAllDeviceKeys() async throws {
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.fcmToken: "fcm-token",
        StorageKey.lastPermissionStatus: true,
        StorageKey.notificationPreference: false,
    ])
    let service = makeService(transport: FakeTransport(responses: []), store: store)

    await service.clearDeviceData()

    #expect(store.string(forKey: StorageKey.deviceId) == nil)
    #expect(store.string(forKey: StorageKey.fcmToken) == nil)
    #expect(store.bool(forKey: StorageKey.lastPermissionStatus) == nil)
    #expect(store.bool(forKey: StorageKey.notificationPreference) == nil)
}
