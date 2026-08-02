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

    @Test func sdkVersionIsSet() {
        #expect(PushFire.sdkVersion == "0.1.0")
    }
}
