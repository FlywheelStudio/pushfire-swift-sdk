import Foundation
import Testing

@testable import PushFire

// Every Flutter counterpart implements `hashCode`, so the models are usable as map keys
// and set members there. These conformances close that gap: without them a caller
// cannot deduplicate a device list or key a cache by subscriber.

private func makeDevice(id: String = "dev_1", token: String = "fcm-token") -> Device {
    Device(
        id: id,
        fcmToken: token,
        os: "ios",
        osVersion: "17.0",
        language: "en",
        manufacturer: "Apple",
        model: "iPhone",
        appVersion: "1.0.0",
        pushNotificationEnabled: true
    )
}

@Test func devicesDeduplicateInASet() {
    let set: Set<Device> = [makeDevice(), makeDevice(), makeDevice(id: "dev_2")]

    #expect(set.count == 2)
    #expect(set.contains(makeDevice()))
}

@Test func equalValuesHashEqually() {
    // The invariant that makes a Set work at all: equal values must land in the same
    // bucket. Synthesis guarantees it, so this is a guard against someone later hand
    // rolling `==` and forgetting `hash(into:)`.
    #expect(makeDevice().hashValue == makeDevice().hashValue)

    let a = Subscriber(id: "s1", deviceId: "d1", externalId: "u1", name: "Jane")
    let b = Subscriber(id: "s1", deviceId: "d1", externalId: "u1", name: "Jane")
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
}

@Test func subscribersKeyADictionary() {
    let subscriber = Subscriber(id: "s1", deviceId: "d1", externalId: "u1")
    var lastSeen: [Subscriber: Date] = [:]
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    lastSeen[subscriber] = stamp

    #expect(lastSeen[Subscriber(id: "s1", deviceId: "d1", externalId: "u1")] == stamp)
}

@Test func metadataCarryingSubscribersHash() {
    // Subscriber.metadata is [String: JSONValue], so the whole nested JSON tree has to
    // hash for the outer type to. This is the case most likely to break.
    let metadata: [String: JSONValue] = [
        "plan": .string("premium"),
        "seats": .int(4),
        "beta": .bool(true),
        "scores": .array([.double(1.5), .null]),
        "nested": .object(["a": .string("b")]),
    ]
    let a = Subscriber(id: "s1", deviceId: "d1", externalId: "u1", metadata: metadata)
    let b = Subscriber(id: "s1", deviceId: "d1", externalId: "u1", metadata: metadata)

    #expect(Set([a, b]).count == 1)
}

@Test func everyStoredPropertyParticipatesInEquality() {
    // The mistake these conformances are exposed to: someone later hand-writes `==` or
    // `hash(into:)` and forgets a field, silently collapsing distinct values in a Set.
    // One negative case per field-bearing model is worth more than the positive ones.
    #expect(Set([makeDevice(), makeDevice(token: "other-token")]).count == 2)

    let base = Subscriber(id: "s1", deviceId: "d1", externalId: "u1", name: "Jane")
    #expect(Set([base, base.with(name: "Joan")]).count == 2)

    #expect(
        Set([
            NotificationStatus(isPermissionGranted: true, isEnabled: true),
            NotificationStatus(isPermissionGranted: true, isEnabled: false),
        ]).count == 2
    )
}

@Test func naNInMetadataDoesNotBreakSetMembership() {
    // Synthesised Hashable inherits IEEE semantics, where NaN != NaN, so a subscriber
    // carrying one could be inserted twice and then never found again — defeating the
    // whole point of the conformance. NaN is reachable caller input: APIClient
    // explicitly defends against JSONValue.double(.nan) at encode time.
    let withNaN = Subscriber(
        id: "s1", deviceId: "d1", externalId: "u1", metadata: ["score": .double(.nan)])
    let same = Subscriber(
        id: "s1", deviceId: "d1", externalId: "u1", metadata: ["score": .double(.nan)])

    #expect(withNaN == same)
    #expect(Set([withNaN, same]).count == 1)
    #expect(Set([withNaN]).contains(same))
}

@Test func negativeZeroHashesAsZero() {
    // -0.0 == 0.0 is true, so they must hash alike or the Set invariant breaks.
    #expect(JSONValue.double(-0.0) == JSONValue.double(0.0))
    #expect(Set([JSONValue.double(-0.0), JSONValue.double(0.0)]).count == 1)
}

@Test func distinctNumbersStayDistinct() {
    // The NaN handling must not flatten ordinary values into each other.
    #expect(JSONValue.double(1.5) != JSONValue.double(2.5))
    #expect(JSONValue.double(.nan) != JSONValue.double(1.5))
    #expect(JSONValue.int(1) != JSONValue.double(1.0))
    #expect(Set([JSONValue.double(.infinity), JSONValue.double(-.infinity)]).count == 2)
}

@Test func tagsDeduplicateInASet() {
    let tag = SubscriberTag(tagId: "plan", subscriberId: "s1", value: "premium")
    let same = SubscriberTag(tagId: "plan", subscriberId: "s1", value: "premium")
    let other = SubscriberTag(tagId: "plan", subscriberId: "s1", value: "free")

    #expect(Set([tag, same, other]).count == 2)
}

@Test func notificationStatusHashes() {
    let granted = NotificationStatus(isPermissionGranted: true, isEnabled: true)
    let denied = NotificationStatus(isPermissionGranted: false, isEnabled: true)

    #expect(Set([granted, granted, denied]).count == 2)
}

@Test func eventsDeduplicateInASet() {
    // Makes an event log deduplicable, which is the point of hashing the payloads.
    let events: Set<PushFireEvent> = [
        .deviceRegistered(makeDevice()),
        .deviceRegistered(makeDevice()),
        .pushTokenRefreshed("token"),
        .subscriberLoggedOut,
    ]

    #expect(events.count == 3)
}

@Test func workflowRequestsHash() {
    let target = WorkflowTarget(type: .subscribers, values: ["s1"])
    let a = WorkflowExecutionRequest(workflowId: "w1", type: .immediate, target: target)
    let b = WorkflowExecutionRequest(workflowId: "w1", type: .immediate, target: target)

    #expect(Set([a, b]).count == 1)
}

@Test func bulkResultsHash() {
    let result = BulkTagResult(
        succeeded: [SubscriberTag(tagId: "plan", subscriberId: "s1", value: "premium")],
        failed: [BulkTagResult.Failure(tagId: "region", message: "nope")]
    )
    let same = BulkTagResult(
        succeeded: [SubscriberTag(tagId: "plan", subscriberId: "s1", value: "premium")],
        failed: [BulkTagResult.Failure(tagId: "region", message: "nope")]
    )

    #expect(Set([result, same]).count == 1)
}
