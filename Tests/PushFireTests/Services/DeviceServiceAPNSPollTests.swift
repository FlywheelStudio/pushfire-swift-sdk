import Foundation
import Testing

@testable import PushFire

/// The APNs poll window has to match the Flutter SDK's, or the same device on the same
/// slow network registers on Android and silently doesn't on iOS.
///
/// Flutter checks once, then retries up to 10 times with a 500ms delay before each
/// retry: 11 checks spanning 5.0 seconds. These tests pin the Swift side to the same
/// counts, using a 1ms interval so they don't actually wait.
private func makeService(
    tokens: FakeTokenProvider,
    transport: FakeTransport = FakeTransport(responses: []),
    attempts: Int = 11
) -> DeviceService {
    let config = PushFireConfiguration(apiKey: "k", requestNotificationPermission: false)
    return DeviceService(
        apiClient: APIClient(
            config: config,
            transport: transport,
            logger: PushFireLogger(enabled: false)
        ),
        config: config,
        store: FakeStore(),
        deviceInfo: FakeDeviceInfoProvider(),
        permissions: FakePermissionProvider(status: .authorized),
        tokens: tokens,
        logger: PushFireLogger(enabled: false),
        apnsPollInterval: .milliseconds(1),
        apnsPollAttempts: attempts
    )
}

@Test func apnsPollDefaultMatchesTheFlutterWindow() {
    // Asserts the shipped defaults, not the shortened ones the tests below inject.
    // Flutter's 1 initial check plus 10 retries is 11 checks, and the 10 gaps between
    // them at 500ms are the 5.0 seconds a late token has to arrive in.
    #expect(DeviceService.defaultAPNSPollAttempts == 11)
    #expect(DeviceService.defaultAPNSPollInterval == .milliseconds(500))

    let totalWaitNanoseconds =
        UInt64(DeviceService.defaultAPNSPollAttempts - 1)
        * DeviceService.defaultAPNSPollInterval.nanoseconds
    #expect(totalWaitNanoseconds == 5_000_000_000)
}

@Test func pollsElevenTimesBeforeGivingUp() async throws {
    // Token never arrives: simulator, offline, or registration never fired.
    let tokens = FakeTokenProvider(apns: nil, fcm: "fcm-token")
    let service = makeService(tokens: tokens)

    let device = try await service.registerDevice()

    // Registration gives up quietly rather than throwing — the device registers later
    // when onTokenRefresh fires.
    #expect(device == nil)
    #expect(tokens.apnsCallCount == 11)
}

@Test func stopsPollingAsSoonAsTheTokenArrives() async throws {
    let tokens = FakeTokenProvider(apns: nil, fcm: "fcm-token")
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let service = makeService(tokens: tokens, transport: transport)

    // Arrives on the third check, the way Apple delivers it a moment after
    // registerForRemoteNotifications.
    Task {
        while tokens.apnsCallCount < 3 {
            try? await Task.sleep(nanoseconds: 200_000)
        }
        tokens.setAPNS("apns-token")
    }

    let device = try await service.registerDevice()

    #expect(device?.id == "dev_1")
    #expect(tokens.apnsCallCount < 11, "should not keep polling after the token lands")
}

@Test func doesNotPollWhenTheTokenIsAlreadyThere() async throws {
    let tokens = FakeTokenProvider(apns: "apns-token", fcm: "fcm-token")
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let service = makeService(tokens: tokens, transport: transport)

    _ = try await service.registerDevice()

    #expect(tokens.apnsCallCount == 1)
}
