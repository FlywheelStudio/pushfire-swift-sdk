import Foundation
import Testing

@testable import PushFire

private func makeCore(
    transport: FakeTransport,
    store: FakeStore = FakeStore(),
    permissions: FakePermissionProvider = FakePermissionProvider(status: .authorized),
    tokens: FakeTokenProvider = FakeTokenProvider(),
    lifecycle: FakeLifecycleObserver = FakeLifecycleObserver(),
    auth: FakeAuthProvider? = nil
) -> PushFireCore {
    PushFireCore(
        config: PushFireConfiguration(apiKey: "k", requestNotificationPermission: false),
        transport: transport,
        store: store,
        deviceInfo: FakeDeviceInfoProvider(),
        permissions: permissions,
        tokens: tokens,
        lifecycle: lifecycle,
        authProvider: auth,
        apnsPollInterval: .milliseconds(1),
        apnsPollAttempts: 2
    )
}

/// Waits for the next event, failing rather than hanging if none arrives.
///
/// Nanoseconds rather than `Duration`: this predates the package's iOS 16 floor, back
/// when `Duration` and `Task.sleep(for:)` (iOS 16+) were unavailable at the package's
/// then-iOS-15 floor. It is kept as-is because it works and there's no value in
/// churning it now that the floor has moved.
private func nextEvent(
    _ stream: AsyncStream<PushFireEvent>,
    timeoutNanoseconds: UInt64 = 2_000_000_000
) async -> PushFireEvent? {
    await withTaskGroup(of: PushFireEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

@Test func startRegistersDeviceAndEmitsEvent() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let core = makeCore(transport: transport)
    let events = await core.eventStream()

    await core.start()

    let device = await core.currentDevice()
    #expect(device?.id == "dev_1")

    let event = await nextEvent(events)
    #expect(event == .deviceRegistered(device!))

    await core.shutdown()
}

@Test func startSurvivesFailedRegistration() async throws {
    // A failed auto-registration must not stop the SDK from working.
    let transport = FakeTransport(response: .failure(500, #"{"message":"nope"}"#))
    let core = makeCore(transport: transport)

    await core.start()

    let device = await core.currentDevice()
    #expect(device == nil)

    await core.shutdown()
}

@Test func tokenRefreshReRegistersAndEmits() async throws {
    let transport = FakeTransport(
        responses: [.ok(#"{"id":"dev_1"}"#), .ok("{}"), .ok("{}")]
    )
    let tokens = FakeTokenProvider()
    let core = makeCore(transport: transport, tokens: tokens)
    let events = await core.eventStream()

    await core.start()
    _ = await nextEvent(events)

    tokens.setFCM("rotated-token")
    tokens.emitRefresh("rotated-token")

    var sawRefresh = false
    for _ in 0..<4 {
        if await nextEvent(events) == .pushTokenRefreshed("rotated-token") {
            sawRefresh = true
            break
        }
    }
    #expect(sawRefresh)

    await core.shutdown()
}

@Test func foregroundSyncsPermissionChange() async throws {
    let transport = FakeTransport(responses: [.ok(#"{"id":"dev_1"}"#), .ok("{}")])
    let permissions = FakePermissionProvider(status: .authorized)
    let lifecycle = FakeLifecycleObserver()
    let core = makeCore(transport: transport, permissions: permissions, lifecycle: lifecycle)
    let events = await core.eventStream()

    await core.start()
    _ = await nextEvent(events)

    permissions.setStatus(.denied)
    lifecycle.emitDidBecomeActive()

    _ = await nextEvent(events)

    let recorded = await transport.recorded
    #expect(recorded.count == 2)
    #expect(recorded[1].url?.lastPathComponent == "update-device")

    await core.shutdown()
}

@Test func authSignInLogsSubscriberIn() async throws {
    let transport = FakeTransport(
        responses: [.ok(#"{"id":"dev_1"}"#), .ok(#"{"id":"sub_1"}"#)]
    )
    let auth = FakeAuthProvider()
    let core = makeCore(transport: transport, auth: auth)

    await core.start()
    auth.emit(.signedIn(AuthUser(id: "u_1", name: "Jane", email: "", phone: nil)))

    var subscriber: Subscriber?
    for _ in 0..<20 {
        subscriber = await core.currentSubscriber()
        if subscriber != nil { break }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(subscriber?.externalId == "u_1")
    let data = try await transport.requestData(at: 1)
    #expect(data["name"] as? String == "Jane")
    // Empty strings from the auth system are normalised away, never sent as "".
    #expect(data["email"] == nil)

    await core.shutdown()
}

@Test func authSignInSkipsWhenAlreadyLoggedInAsSameUser() async throws {
    let transport = FakeTransport(
        responses: [.ok(#"{"id":"dev_1"}"#), .ok(#"{"id":"sub_1"}"#)]
    )
    let auth = FakeAuthProvider()
    let core = makeCore(transport: transport, auth: auth)

    await core.start()
    auth.emit(.signedIn(AuthUser(id: "u_1")))
    for _ in 0..<20 where await core.currentSubscriber() == nil {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    auth.emit(.signedIn(AuthUser(id: "u_1")))
    try? await Task.sleep(nanoseconds: 200_000_000)

    let recorded = await transport.recorded
    #expect(recorded.count == 2)

    await core.shutdown()
}

@Test func resetClearsDeviceAndSubscriber() async throws {
    let transport = FakeTransport(
        responses: [.ok(#"{"id":"dev_1"}"#), .ok(#"{"id":"sub_1"}"#), .ok("{}")]
    )
    let store = FakeStore()
    let core = makeCore(transport: transport, store: store)

    await core.start()
    _ = try await core.login(
        externalId: "u_1", name: nil, email: nil, phone: nil, metadata: nil
    )

    try await core.reset()

    #expect(store.string(forKey: StorageKey.deviceId) == nil)
    #expect(store.string(forKey: StorageKey.subscriberId) == nil)
    let device = await core.currentDevice()
    #expect(device == nil)

    await core.shutdown()
}
