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

@Test func withKeepsExistingValuesForNilArguments() {
    // `updateSubscriber` builds the new local record with this, passing nil for every
    // field the caller left out. Treating nil as "clear it" there would wipe stored
    // fields the caller never mentioned.
    let subscriber = Subscriber(
        id: "sub_1",
        deviceId: "dev_1",
        externalId: "u_1",
        name: "Jane",
        email: "j@x.com",
        phone: "+100",
        metadata: ["tier": .string("gold")]
    )

    let updated = subscriber.with(name: "Jane Doe")

    #expect(updated.name == "Jane Doe")
    #expect(updated.email == "j@x.com")
    #expect(updated.phone == "+100")
    #expect(updated.metadata?["tier"] == .string("gold"))
    // Identity fields are never rewritten.
    #expect(updated.id == "sub_1")
    #expect(updated.deviceId == "dev_1")
    #expect(updated.externalId == "u_1")

    // Every field behaves the same way, including the first one.
    let emailOnly = subscriber.with(email: "new@x.com")
    #expect(emailOnly.name == "Jane")
    #expect(emailOnly.email == "new@x.com")
}

@Test func metadataRoundTripsNestedValues() throws {
    // Metadata is caller-defined, so nested objects, arrays and nulls are the
    // realistic shapes — not just flat strings.
    let metadata: [String: JSONValue] = [
        "flat": .string("a"),
        "nested": .object(["inner": .array([.int(1), .bool(true), .null])]),
        "missing": .null,
    ]
    let subscriber = Subscriber(externalId: "u_1", metadata: metadata)

    let data = try JSONEncoder().encode(subscriber)
    let decoded = try JSONDecoder().decode(Subscriber.self, from: data)

    #expect(decoded.metadata == metadata)
    #expect(
        decoded.metadata?["nested"] == .object(["inner": .array([.int(1), .bool(true), .null])]))
    #expect(decoded.metadata?["missing"] == .null)
}

@Test func metadataDecodesEveryJSONShapeFromTheWire() throws {
    // Metadata arrives from the server (and from the local store) as raw JSON, so the
    // decoder's type probe has to classify every shape a caller can send.
    let json = """
        {
          "externalId": "u_1",
          "metadata": {
            "text": "hello",
            "count": 7,
            "ratio": 1.5,
            "negative": -2,
            "flag": false,
            "nothing": null,
            "list": [1, "two", 3.5, true, null, [9], {"deep": "value"}],
            "object": {"nested": {"deeper": [1, 2]}}
          }
        }
        """

    let subscriber = try JSONDecoder().decode(Subscriber.self, from: Data(json.utf8))
    let metadata = try #require(subscriber.metadata)

    #expect(metadata["text"] == .string("hello"))
    // Int is probed before Double, so a whole number stays an Int and does not come
    // back as "7.0" when it is re-encoded.
    #expect(metadata["count"] == .int(7))
    #expect(metadata["negative"] == .int(-2))
    #expect(metadata["ratio"] == .double(1.5))
    // Bool is probed before Int, so `false` must not degrade into 0.
    #expect(metadata["flag"] == .bool(false))
    #expect(metadata["nothing"] == .null)
    #expect(
        metadata["list"]
            == .array([
                .int(1), .string("two"), .double(3.5), .bool(true), .null,
                .array([.int(9)]), .object(["deep": .string("value")]),
            ])
    )
    #expect(
        metadata["object"]
            == .object(["nested": .object(["deeper": .array([.int(1), .int(2)])])])
    )
}

@Test func metadataSurvivesAnEncodeDecodeRoundTrip() throws {
    // The stored subscriber blob is written with this encoder and read back with this
    // decoder, so a shape that changes across the round trip silently rewrites a
    // caller's metadata between launches.
    let metadata: [String: JSONValue] = [
        "text": .string("hello"),
        "count": .int(7),
        "ratio": .double(1.5),
        "flag": .bool(true),
        "nothing": .null,
        "list": .array([.int(1), .array([.string("x")]), .object(["k": .null])]),
        "object": .object(["nested": .object(["deeper": .bool(false)])]),
    ]

    let data = try JSONEncoder().encode(Subscriber(externalId: "u_1", metadata: metadata))
    let decoded = try JSONDecoder().decode(Subscriber.self, from: data)

    #expect(decoded.metadata == metadata)
}
