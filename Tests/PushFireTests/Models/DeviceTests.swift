import Foundation
import Testing

@testable import PushFire

@Test func deviceOmitsIDWhenNil() throws {
    let device = Device(
        id: nil,
        fcmToken: "tok",
        os: "ios",
        osVersion: "18.0",
        language: "en_US",
        manufacturer: "Apple",
        model: "iPhone",
        appVersion: "1.2.3",
        pushNotificationEnabled: true
    )

    let data = try JSONEncoder().encode(device)
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(json["id"] == nil)
    #expect(json["fcmToken"] as? String == "tok")
    #expect(json["os"] as? String == "ios")
    #expect(json["pushNotificationEnabled"] as? Bool == true)
}

@Test func deviceIncludesIDWhenPresent() throws {
    let device = Device(
        id: "dev_1",
        fcmToken: "tok",
        os: "ios",
        osVersion: "18.0",
        language: "en_US",
        manufacturer: "Apple",
        model: "iPhone",
        appVersion: "1.2.3",
        pushNotificationEnabled: false
    )

    let data = try JSONEncoder().encode(device)
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(json["id"] as? String == "dev_1")
}
