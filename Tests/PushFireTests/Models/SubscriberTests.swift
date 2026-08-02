import Foundation
import Testing

@testable import PushFire

@Test func subscriberRoundTripsMetadata() throws {
    let subscriber = Subscriber(
        id: "sub_1",
        deviceId: "dev_1",
        externalId: "u_1",
        name: "Jane",
        email: nil,
        phone: nil,
        metadata: ["tier": .string("gold"), "seats": .int(3)]
    )

    let data = try JSONEncoder().encode(subscriber)
    let decoded = try JSONDecoder().decode(Subscriber.self, from: data)

    #expect(decoded == subscriber)
    #expect(decoded.metadata?["tier"] == .string("gold"))
}

@Test func subscriberOmitsNilFields() throws {
    let subscriber = Subscriber(externalId: "u_1")

    let data = try JSONEncoder().encode(subscriber)
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(json["externalId"] as? String == "u_1")
    #expect(json["name"] == nil)
    #expect(json["metadata"] == nil)
}
