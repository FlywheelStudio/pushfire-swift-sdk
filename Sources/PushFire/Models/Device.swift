import Foundation

/// A device registered with PushFire.
public struct Device: Codable, Sendable, Equatable {
    public let id: String?
    public let fcmToken: String
    public let os: String
    public let osVersion: String
    public let language: String
    public let manufacturer: String
    public let model: String
    public let appVersion: String
    public let pushNotificationEnabled: Bool

    public init(
        id: String? = nil,
        fcmToken: String,
        os: String,
        osVersion: String,
        language: String,
        manufacturer: String,
        model: String,
        appVersion: String,
        pushNotificationEnabled: Bool
    ) {
        self.id = id
        self.fcmToken = fcmToken
        self.os = os
        self.osVersion = osVersion
        self.language = language
        self.manufacturer = manufacturer
        self.model = model
        self.appVersion = appVersion
        self.pushNotificationEnabled = pushNotificationEnabled
    }

    /// Returns a copy with the given fields replaced.
    public func with(
        id: String? = nil,
        fcmToken: String? = nil,
        pushNotificationEnabled: Bool? = nil
    ) -> Device {
        Device(
            id: id ?? self.id,
            fcmToken: fcmToken ?? self.fcmToken,
            os: os,
            osVersion: osVersion,
            language: language,
            manufacturer: manufacturer,
            model: model,
            appVersion: appVersion,
            pushNotificationEnabled: pushNotificationEnabled ?? self.pushNotificationEnabled
        )
    }
}
