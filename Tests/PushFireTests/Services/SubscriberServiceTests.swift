import Foundation
import Testing

@testable import PushFire

private func makeServices(
    transport: FakeTransport,
    store: FakeStore = FakeStore([StorageKey.deviceId: "dev_1", StorageKey.fcmToken: "tok"])
) -> (SubscriberService, FakeStore) {
    let config = PushFireConfiguration(apiKey: "k", requestNotificationPermission: false)
    let logger = PushFireLogger(enabled: false)
    let apiClient = APIClient(config: config, transport: transport, logger: logger)
    let deviceService = DeviceService(
        apiClient: apiClient,
        config: config,
        store: store,
        deviceInfo: FakeDeviceInfoProvider(),
        permissions: FakePermissionProvider(status: .authorized),
        tokens: FakeTokenProvider(),
        logger: logger,
        apnsPollInterval: .milliseconds(1),
        apnsPollAttempts: 2
    )
    let service = SubscriberService(
        apiClient: apiClient,
        deviceService: deviceService,
        store: store,
        logger: logger
    )
    return (service, store)
}

@Test func loginSendsDeviceIDAndPersistsSubscriber() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"sub_1"}"#))
    let (service, store) = makeServices(transport: transport)

    let subscriber = try await service.login(
        externalId: "u_1",
        name: "Jane",
        email: "j@x.com",
        phone: nil,
        metadata: ["tier": .string("gold")]
    )

    #expect(subscriber.id == "sub_1")
    #expect(subscriber.deviceId == "dev_1")

    let recorded = await transport.recorded
    #expect(recorded[0].url?.lastPathComponent == "login-subscriber")
    #expect(recorded[0].httpMethod == "POST")

    let data = try await transport.requestData(at: 0)
    #expect(data["deviceId"] as? String == "dev_1")
    #expect(data["externalId"] as? String == "u_1")
    #expect(data["name"] as? String == "Jane")
    #expect(data["phone"] == nil)

    #expect(store.string(forKey: StorageKey.subscriberId) == "sub_1")
    let restored = await service.currentSubscriber()
    #expect(restored?.externalId == "u_1")
    #expect(restored?.metadata?["tier"] == .string("gold"))
}

@Test func loginThrowsWhenDeviceNotRegistered() async throws {
    let transport = FakeTransport(responses: [])
    let (service, _) = makeServices(transport: transport, store: FakeStore())

    await #expect(throws: PushFireError.self) {
        _ = try await service.login(
            externalId: "u_1", name: nil, email: nil, phone: nil, metadata: nil
        )
    }
}

@Test func loginThrowsWhenNoSubscriberIDReturned() async throws {
    let transport = FakeTransport(response: .ok(#"{"ok":true}"#))
    let (service, _) = makeServices(transport: transport)

    await #expect(throws: PushFireError.self) {
        _ = try await service.login(
            externalId: "u_1", name: nil, email: nil, phone: nil, metadata: nil
        )
    }
}

@Test func updateResendsStoredExternalID() async throws {
    let transport = FakeTransport(responses: [.ok(#"{"id":"sub_1"}"#), .ok("{}")])
    let (service, _) = makeServices(transport: transport)

    _ = try await service.login(
        externalId: "u_1", name: "Jane", email: nil, phone: nil, metadata: nil
    )
    let updated = try await service.updateSubscriber(
        name: "Jane Doe", email: nil, phone: nil, metadata: nil
    )

    #expect(updated.name == "Jane Doe")
    #expect(updated.externalId == "u_1")

    let recorded = await transport.recorded
    #expect(recorded[1].url?.lastPathComponent == "update-subscriber")
    #expect(recorded[1].httpMethod == "PATCH")

    let data = try await transport.requestData(at: 1)
    #expect(data["id"] as? String == "sub_1")
    #expect(data["externalId"] as? String == "u_1")
    #expect(data["name"] as? String == "Jane Doe")
}

@Test func updateThrowsWhenNoSubscriberLoggedIn() async throws {
    let transport = FakeTransport(responses: [])
    let (service, _) = makeServices(transport: transport)

    await #expect(throws: PushFireError.self) {
        _ = try await service.updateSubscriber(
            name: "x", email: nil, phone: nil, metadata: nil
        )
    }
}

@Test func logoutSendsDeviceAndSubscriberThenClears() async throws {
    let transport = FakeTransport(responses: [.ok(#"{"id":"sub_1"}"#), .ok("{}")])
    let (service, store) = makeServices(transport: transport)

    _ = try await service.login(
        externalId: "u_1", name: nil, email: nil, phone: nil, metadata: nil
    )
    try await service.logout()

    let data = try await transport.requestData(at: 1)
    #expect(data["deviceId"] as? String == "dev_1")
    #expect(data["subscriberId"] as? String == "sub_1")

    #expect(store.string(forKey: StorageKey.subscriberId) == nil)
    #expect(store.string(forKey: StorageKey.subscriberData) == nil)
    let isLoggedIn = await service.isLoggedIn()
    #expect(isLoggedIn == false)
}

@Test func logoutClearsLocalStateEvenWhenServerFails() async throws {
    let transport = FakeTransport(
        responses: [.ok(#"{"id":"sub_1"}"#), .failure(500, #"{"message":"boom"}"#)]
    )
    let (service, store) = makeServices(transport: transport)

    _ = try await service.login(
        externalId: "u_1", name: nil, email: nil, phone: nil, metadata: nil
    )

    await #expect(throws: PushFireError.self) {
        try await service.logout()
    }

    #expect(store.string(forKey: StorageKey.subscriberId) == nil)
    let isLoggedIn = await service.isLoggedIn()
    #expect(isLoggedIn == false)
}

@Test func logoutWithNoSessionClearsWithoutCallingServer() async throws {
    let transport = FakeTransport(responses: [])
    let (service, _) = makeServices(transport: transport)

    try await service.logout()

    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func persistWritesBothKeysOrNeither() async throws {
    // Writing the id first and then failing to encode would leave subscriberId()
    // reporting a logged-in user that currentSubscriber() and isLoggedIn() cannot see.
    // Nothing later reconciles that split, so persist has to be all-or-nothing.
    let transport = FakeTransport(response: .ok("{}"))
    let (service, store) = makeServices(transport: transport)

    let unencodable = Subscriber(
        id: "sub_1",
        deviceId: "dev_1",
        externalId: "ext_1",
        metadata: ["broken": .double(.nan)]
    )

    await service.persist(unencodable)

    #expect(store.string(forKey: StorageKey.subscriberId) == nil)
    #expect(store.string(forKey: StorageKey.subscriberData) == nil)
    #expect(await service.isLoggedIn() == false)
    #expect(await service.subscriberId() == nil)
}

@Test func currentSubscriberReturnsNilForAnUndecodableStoredBlob() async throws {
    // Corrupted or schema-drifted local state must degrade to "nobody is logged in".
    // Throwing here would take down every caller — `isLoggedIn()`, tag writes, the
    // auth observer — none of which can throw.
    let transport = FakeTransport(responses: [])
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.subscriberId: "sub_1",
        StorageKey.subscriberData: #"{"id":"sub_1","externalId""#,
    ])
    let (service, _) = makeServices(transport: transport, store: store)

    #expect(await service.currentSubscriber() == nil)
    #expect(await service.isLoggedIn() == false)
    // The id lives under its own key and is untouched by the unreadable blob.
    #expect(await service.subscriberId() == "sub_1")
}

@Test func currentSubscriberReturnsNilWhenStoredBlobIsMissingRequiredFields() async throws {
    // Valid JSON of the wrong shape — what an older or newer SDK version could leave
    // behind — takes the same path as outright corruption.
    let transport = FakeTransport(responses: [])
    let store = FakeStore([
        StorageKey.deviceId: "dev_1",
        StorageKey.subscriberData: #"{"id":"sub_1"}"#,
    ])
    let (service, _) = makeServices(transport: transport, store: store)

    #expect(await service.currentSubscriber() == nil)
    #expect(await service.isLoggedIn() == false)
}

@Test func persistWritesBothKeysOnSuccess() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let (service, store) = makeServices(transport: transport)

    let subscriber = Subscriber(id: "sub_1", deviceId: "dev_1", externalId: "ext_1")

    await service.persist(subscriber)

    #expect(store.string(forKey: StorageKey.subscriberId) == "sub_1")
    #expect(store.string(forKey: StorageKey.subscriberData) != nil)
    #expect(await service.isLoggedIn() == true)
}
