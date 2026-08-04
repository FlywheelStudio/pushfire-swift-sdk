import Foundation
import Testing

@testable import PushFire

/// The APNs poll window has to match the Flutter SDK's, or the same device on the same
/// slow network registers on Android and silently doesn't on iOS.
///
/// Flutter checks once, then retries up to 10 times with a 500ms delay before each
/// retry: 11 checks separated by 10 gaps, spanning 5.0 seconds. Both counts matter, and
/// neither is observable from the other, so these tests pin them separately.

/// Records the gaps between token checks instead of waiting them out.
private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var intervals: [PollInterval] = []

    var count: Int { lock.withLock { intervals.count } }
    var total: UInt64 { lock.withLock { intervals.reduce(0) { $0 + $1.nanoseconds } } }

    var sleeper: @Sendable (PollInterval) async -> Void {
        { interval in self.lock.withLock { self.intervals.append(interval) } }
    }
}

private func makeService(
    tokens: FakeTokenProvider,
    transport: FakeTransport = FakeTransport(responses: []),
    attempts: Int = DeviceService.defaultAPNSPollAttempts,
    interval: PollInterval = DeviceService.defaultAPNSPollInterval,
    recorder: SleepRecorder = SleepRecorder()
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
        apnsPollInterval: interval,
        apnsPollAttempts: attempts,
        // Recorded rather than performed, so these tests pin the real shipped window
        // without spending 5 seconds doing it.
        sleeper: recorder.sleeper
    )
}

@Test func shippedPollWindowMatchesFlutter() async throws {
    // Drives the defaults production uses, not values the test picked.
    let recorder = SleepRecorder()
    let tokens = FakeTokenProvider(apns: nil, fcm: "fcm-token")
    let service = makeService(tokens: tokens, recorder: recorder)

    let device = try await service.registerDevice()

    // Gives up quietly rather than throwing: the device registers later, when
    // onTokenRefresh fires.
    #expect(device == nil)
    #expect(tokens.apnsCallCount == 11, "Flutter checks 11 times")
    #expect(recorder.count == 10, "11 checks are separated by 10 gaps, not 11")
    #expect(recorder.total == 5_000_000_000, "the window is 5.0 seconds")
}

@Test func coreUsesTheShippedPollWindow() {
    // The constants are only worth asserting if production reaches them. PushFireCore
    // previously carried its own copies of the literals, so the window could drift back
    // with this suite still green.
    #expect(DeviceService.defaultAPNSPollAttempts == 11)
    #expect(DeviceService.defaultAPNSPollInterval == .milliseconds(500))
}

@Test func stopsPollingAsSoonAsTheTokenArrives() async throws {
    // Apple delivers the token a moment after registerForRemoteNotifications: nil for
    // the first two checks, present on the third.
    let tokens = FakeTokenProvider(
        apns: "apns-token", fcm: "fcm-token", apnsAvailableAfterCalls: 2)
    let recorder = SleepRecorder()
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let service = makeService(tokens: tokens, transport: transport, recorder: recorder)

    let device = try await service.registerDevice()

    #expect(device?.id == "dev_1")
    #expect(tokens.apnsCallCount == 3)
    #expect(recorder.count == 2, "one gap before each retry, none after the hit")
}

@Test func acceptsATokenThatArrivesOnTheFinalAttempt() async throws {
    // The boundary: the last check must still count, and must not be followed by a
    // pointless sleep.
    let tokens = FakeTokenProvider(
        apns: "apns-token", fcm: "fcm-token", apnsAvailableAfterCalls: 10)
    let recorder = SleepRecorder()
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let service = makeService(tokens: tokens, transport: transport, recorder: recorder)

    let device = try await service.registerDevice()

    #expect(device?.id == "dev_1")
    #expect(tokens.apnsCallCount == 11)
    #expect(recorder.count == 10)
}

@Test func doesNotPollWhenTheTokenIsAlreadyThere() async throws {
    let tokens = FakeTokenProvider(apns: "apns-token", fcm: "fcm-token")
    let recorder = SleepRecorder()
    let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
    let service = makeService(tokens: tokens, transport: transport, recorder: recorder)

    _ = try await service.registerDevice()

    #expect(tokens.apnsCallCount == 1)
    #expect(recorder.count == 0)
}

@Test func singleAttemptNeverSleeps() async throws {
    // Degenerate case: with one check there is no gap to wait, and the `attempt < n - 1`
    // guard has to skip the sleep entirely rather than underflow.
    let tokens = FakeTokenProvider(apns: nil, fcm: "fcm-token")
    let recorder = SleepRecorder()
    let service = makeService(tokens: tokens, attempts: 1, recorder: recorder)

    let device = try await service.registerDevice()

    #expect(device == nil)
    #expect(tokens.apnsCallCount == 1)
    #expect(recorder.count == 0)
}

@Test func skipsTheFCMFetchWhenNoAPNSTokenArrives() async throws {
    // Asking FirebaseMessaging for an FCM token before APNs lands is the failure this
    // whole poll exists to avoid, so the fetch must not happen at all.
    let tokens = FakeTokenProvider(apns: nil, fcm: "fcm-token")
    let service = makeService(tokens: tokens)

    _ = try await service.registerDevice()

    #expect(tokens.fcmCallCount == 0)
}
