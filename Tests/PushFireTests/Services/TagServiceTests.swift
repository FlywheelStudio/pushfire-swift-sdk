import Foundation
import Testing

@testable import PushFire

private func makeTagService(
    transport: FakeTransport,
    subscriberId: String? = "sub_1"
) -> TagService {
    let config = PushFireConfiguration(apiKey: "k", requestNotificationPermission: false)
    let logger = PushFireLogger(enabled: false)
    let apiClient = APIClient(config: config, transport: transport, logger: logger)

    var values: [String: Any] = [StorageKey.deviceId: "dev_1", StorageKey.fcmToken: "tok"]
    if let subscriberId {
        values[StorageKey.subscriberId] = subscriberId
    }
    let store = FakeStore(values)

    let deviceService = DeviceService(
        apiClient: apiClient,
        config: config,
        store: store,
        deviceInfo: FakeDeviceInfoProvider(),
        permissions: FakePermissionProvider(status: .authorized),
        tokens: FakeTokenProvider(),
        logger: logger,
        apnsPollInterval: .milliseconds(1),
        apnsPollAttempts: 2
    )
    let subscriberService = SubscriberService(
        apiClient: apiClient,
        deviceService: deviceService,
        store: store,
        logger: logger
    )
    return TagService(
        apiClient: apiClient,
        subscriberService: subscriberService,
        logger: logger
    )
}

@Test func addTagPostsTagPayload() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let service = makeTagService(transport: transport)

    let tag = try await service.addTag("plan", value: "pro")

    #expect(tag == SubscriberTag(tagId: "plan", subscriberId: "sub_1", value: "pro"))

    let recorded = await transport.recorded
    #expect(recorded[0].url?.lastPathComponent == "add-subscriber-tag")
    #expect(recorded[0].httpMethod == "POST")

    let data = try await transport.requestData(at: 0)
    #expect(data["tagId"] as? String == "plan")
    #expect(data["subscriberId"] as? String == "sub_1")
    #expect(data["value"] as? String == "pro")
}

@Test func updateTagPatches() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let service = makeTagService(transport: transport)

    _ = try await service.updateTag("plan", value: "enterprise")

    let recorded = await transport.recorded
    #expect(recorded[0].url?.lastPathComponent == "update-subscriber-tag")
    #expect(recorded[0].httpMethod == "PATCH")
}

@Test func removeTagDeletesWithoutValue() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let service = makeTagService(transport: transport)

    try await service.removeTag("plan")

    let recorded = await transport.recorded
    #expect(recorded[0].url?.lastPathComponent == "remove-subscriber-tag")
    #expect(recorded[0].httpMethod == "DELETE")

    let data = try await transport.requestData(at: 0)
    #expect(data["tagId"] as? String == "plan")
    #expect(data["subscriberId"] as? String == "sub_1")
    #expect(data["value"] == nil)
}

@Test func tagOperationsThrowWhenNoSubscriber() async throws {
    let transport = FakeTransport(responses: [])
    let service = makeTagService(transport: transport, subscriberId: nil)

    await #expect(throws: PushFireError.self) {
        _ = try await service.addTag("plan", value: "pro")
    }

    // Proves the guard ran before any request, rather than the transport throwing.
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func bulkAddReportsPartialFailures() async throws {
    // Divergence 1 from the spec: the Dart silently drops the failures.
    let transport = FakeTransport(
        responses: [.ok("{}"), .failure(400, #"{"message":"Unknown tag"}"#)]
    )
    let service = makeTagService(transport: transport)

    let result = try await service.addTags([("plan", "pro"), ("tier", "gold")])

    #expect(result.succeeded.count == 1)
    #expect(result.succeeded[0].tagId == "plan")
    #expect(result.failed.count == 1)
    #expect(result.failed[0].tagId == "tier")
    #expect(result.failed[0].message == "Unknown tag")
    #expect(result.isCompleteSuccess == false)
}

@Test func bulkAddThrowsWhenEverythingFails() async throws {
    let transport = FakeTransport(
        responses: [
            .failure(400, #"{"message":"a"}"#),
            .failure(400, #"{"message":"b"}"#),
        ]
    )
    let service = makeTagService(transport: transport)

    await #expect(throws: PushFireError.self) {
        _ = try await service.addTags([("plan", "pro"), ("tier", "gold")])
    }
}

@Test func bulkAddSucceedsCompletely() async throws {
    let transport = FakeTransport(responses: [.ok("{}"), .ok("{}")])
    let service = makeTagService(transport: transport)

    let result = try await service.addTags([("plan", "pro"), ("tier", "gold")])

    #expect(result.isCompleteSuccess == true)
    #expect(result.succeeded.count == 2)
}

@Test func bulkRemoveReportsFailures() async throws {
    let transport = FakeTransport(
        responses: [.ok("{}"), .failure(404, #"{"message":"Not found"}"#)]
    )
    let service = makeTagService(transport: transport)

    let result = try await service.removeTags(["plan", "tier"])

    #expect(result.succeeded.map(\.tagId) == ["plan"])
    #expect(result.failed.count == 1)
    #expect(result.failed[0].tagId == "tier")
}

@Test func bulkRemoveReportsSuccesses() async throws {
    let transport = FakeTransport(responses: [.ok("{}"), .ok("{}")])
    let service = makeTagService(transport: transport)

    let result = try await service.removeTags(["plan", "tier"])

    #expect(result.isCompleteSuccess)
    #expect(result.succeeded.map(\.tagId) == ["plan", "tier"])
    #expect(result.failed.isEmpty)
}

@Test func bulkAddWithEmptyArrayMakesNoRequest() async throws {
    let transport = FakeTransport(responses: [])
    let service = makeTagService(transport: transport)

    let result = try await service.addTags([])

    #expect(result.succeeded.isEmpty)
    #expect(result.failed.isEmpty)
    #expect(result.isCompleteSuccess == true)

    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func bulkRemoveThrowsWhenEveryRemovalFails() async throws {
    // Nothing was removed, so returning a "result" would let a caller that only reads
    // `succeeded` treat a total failure as a no-op.
    let transport = FakeTransport(
        responses: [
            .failure(500, #"{"message":"a"}"#),
            .failure(500, #"{"message":"b"}"#),
        ]
    )
    let service = makeTagService(transport: transport)

    do {
        _ = try await service.removeTags(["plan", "tier"])
        Issue.record("expected a throw")
    } catch PushFireError.tag(let message) {
        // Every failed id is named, so the caller knows what is still attached.
        #expect(message == "Failed to remove every tag: plan, tier")
    }
}

@Test func bulkFailureMessageUsesTheDescriptionOfANonAPIError() async throws {
    // Non-API PushFireErrors (a network drop, say) have no `message` payload to lift, so
    // the failure has to report their description rather than a Swift-internal dump.
    // One queued response, two tags: the second write gets a transport-level failure.
    let transport = FakeTransport(responses: [.ok("{}")])
    let service = makeTagService(transport: transport)

    let result = try await service.removeTags(["plan", "tier"])

    #expect(result.succeeded.map(\.tagId) == ["plan"])
    #expect(result.failed.count == 1)
    #expect(
        result.failed[0].message
            == "PushFire network error: FakeTransport ran out of queued responses"
    )
}

@Test func bulkAddFailureMessageUsesTheDescriptionOfANonAPIError() async throws {
    let transport = FakeTransport(responses: [.ok("{}")])
    let service = makeTagService(transport: transport)

    let result = try await service.addTags([("plan", "pro"), ("tier", "gold")])

    #expect(result.failed.count == 1)
    #expect(
        result.failed[0].message
            == "PushFire network error: FakeTransport ran out of queued responses"
    )
}

@Test func bulkRemoveWithEmptyArrayMakesNoRequest() async throws {
    let transport = FakeTransport(responses: [])
    let service = makeTagService(transport: transport)

    let result = try await service.removeTags([])

    #expect(result.succeeded.isEmpty)
    #expect(result.failed.isEmpty)
    #expect(result.isCompleteSuccess == true)

    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}
