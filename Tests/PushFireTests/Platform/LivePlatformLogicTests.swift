import Foundation
import Testing
import UserNotifications

@testable import PushFire

@Test func hexStringFormatsEveryByteAsTwoLowercaseDigits() {
    #expect(FirebasePushTokenProvider.hexString(from: Data([0x00, 0xff, 0x1a])) == "00ff1a")
    #expect(FirebasePushTokenProvider.hexString(from: Data([0x0a])) == "0a")
    #expect(FirebasePushTokenProvider.hexString(from: Data()) == "")
}

@Test func hexStringRoundTripsARealisticTokenLength() {
    // APNs device tokens are 32 bytes; the encoded form must be exactly 64 hex chars.
    let token = Data((0..<32).map { UInt8($0) })
    let hex = FirebasePushTokenProvider.hexString(from: token)

    #expect(hex.count == 64)
    #expect(hex.hasPrefix("000102"))
    #expect(hex.allSatisfy { $0.isHexDigit && !$0.isUppercase })
}

@Test func mapsEveryAuthorizationStatus() {
    #expect(UserNotificationsPermissionProvider.map(.notDetermined) == .notDetermined)
    #expect(UserNotificationsPermissionProvider.map(.denied) == .denied)
    #expect(UserNotificationsPermissionProvider.map(.authorized) == .authorized)
    #expect(UserNotificationsPermissionProvider.map(.provisional) == .provisional)
    #expect(UserNotificationsPermissionProvider.map(.ephemeral) == .ephemeral)
}

@Test func onlyAuthorizedAndProvisionalCountAsEnabled() {
    // Mirrors the Flutter SDK: ephemeral (App Clips) does not deliver notifications.
    #expect(UserNotificationsPermissionProvider.map(.authorized).isEnabled)
    #expect(UserNotificationsPermissionProvider.map(.provisional).isEnabled)
    #expect(!UserNotificationsPermissionProvider.map(.ephemeral).isEnabled)
    #expect(!UserNotificationsPermissionProvider.map(.denied).isEnabled)
    #expect(!UserNotificationsPermissionProvider.map(.notDetermined).isEnabled)
}
