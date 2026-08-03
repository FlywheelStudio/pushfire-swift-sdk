import Foundation
import Testing

@testable import PushFire

@Suite(.serialized)
struct PushFireFacadeTests {
    @Test func sharedThrowsBeforeConfigure() async throws {
        await PushFire.shutdown()

        #expect(throws: PushFireError.self) {
            _ = try PushFire.shared
        }
    }

    @Test func configureRejectsEmptyAPIKey() async throws {
        await PushFire.shutdown()

        await #expect(throws: PushFireError.self) {
            try await PushFire.configure(PushFireConfiguration(apiKey: ""))
        }
    }

    @Test func configureMakesSharedAvailable() async throws {
        await PushFire.shutdown()

        let transport = FakeTransport(response: .ok(#"{"id":"dev_1"}"#))
        await PushFire.configureForTesting(
            core: PushFireCore(
                config: PushFireConfiguration(apiKey: "k", requestNotificationPermission: false),
                transport: transport,
                store: FakeStore(),
                deviceInfo: FakeDeviceInfoProvider(),
                permissions: FakePermissionProvider(status: .authorized),
                tokens: FakeTokenProvider(),
                lifecycle: FakeLifecycleObserver(),
                authProvider: nil,
                apnsPollInterval: .milliseconds(1),
                apnsPollAttempts: 2
            )
        )

        #expect(PushFire.isConfigured)
        let deviceId = try await PushFire.shared.deviceId()
        #expect(deviceId == "dev_1")

        await PushFire.shutdown()
        #expect(PushFire.isConfigured == false)
    }

    @Test func sdkVersionIsSet() async {
        await PushFire.shutdown()

        #expect(PushFire.sdkVersion == "0.1.0")
    }

    @Test func configuringTwiceKeepsTheFirstInstance() async throws {
        await PushFire.shutdown()

        await PushFire.configureForTesting(
            core: PushFireCore(
                config: PushFireConfiguration(apiKey: "k", requestNotificationPermission: false),
                transport: FakeTransport(response: .ok(#"{"id":"dev_1"}"#)),
                store: FakeStore(),
                deviceInfo: FakeDeviceInfoProvider(),
                permissions: FakePermissionProvider(status: .authorized),
                tokens: FakeTokenProvider(),
                lifecycle: FakeLifecycleObserver(),
                authProvider: nil,
                apnsPollInterval: .milliseconds(1),
                apnsPollAttempts: 2
            )
        )
        let first = try await PushFire.shared.deviceId()

        await PushFire.configureForTesting(
            core: PushFireCore(
                config: PushFireConfiguration(apiKey: "k", requestNotificationPermission: false),
                transport: FakeTransport(response: .ok(#"{"id":"dev_2"}"#)),
                store: FakeStore(),
                deviceInfo: FakeDeviceInfoProvider(),
                permissions: FakePermissionProvider(status: .authorized),
                tokens: FakeTokenProvider(),
                lifecycle: FakeLifecycleObserver(),
                authProvider: nil,
                apnsPollInterval: .milliseconds(1),
                apnsPollAttempts: 2
            )
        )
        let second = try await PushFire.shared.deviceId()

        #expect(first == "dev_1")
        // The second configure must not replace the live instance.
        #expect(second == "dev_1")

        await PushFire.shutdown()
    }
}
