import Foundation
import Testing

@testable import PushFire

private let workflowUUID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
private let targetUUID = "550e8400-e29b-41d4-a716-446655440000"

private func makeWorkflowService(_ transport: FakeTransport) -> WorkflowService {
    let config = PushFireConfiguration(apiKey: "k")
    let logger = PushFireLogger(enabled: false)
    return WorkflowService(
        apiClient: APIClient(config: config, transport: transport, logger: logger),
        logger: logger
    )
}

@Test func runsImmediateWorkflowForSubscribers() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"exec_1"}"#))
    let service = makeWorkflowService(transport)

    let response = try await service.run(
        workflowUUID,
        target: .subscribers([targetUUID]),
        at: nil
    )

    #expect(response.id == "exec_1")

    let recorded = await transport.recorded
    #expect(recorded[0].url?.lastPathComponent == "create-workflow-execution")
    #expect(recorded[0].httpMethod == "POST")

    let data = try await transport.requestData(at: 0)
    #expect(data["workflowId"] as? String == workflowUUID)
    #expect(data["type"] as? String == "Immediate")
    #expect(data["scheduledFor"] == nil)

    let target = try #require(data["target"] as? [String: Any])
    #expect(target["type"] as? String == "Subscribers")
    #expect(target["values"] as? [String] == [targetUUID])
}

@Test func runsScheduledWorkflowForSegments() async throws {
    let transport = FakeTransport(response: .ok("{}"))
    let service = makeWorkflowService(transport)

    _ = try await service.run(
        workflowUUID,
        target: .segments([targetUUID]),
        at: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let data = try await transport.requestData(at: 0)
    #expect(data["type"] as? String == "Scheduled")
    #expect(data["scheduledFor"] as? String == "2023-11-14T22:13:20.000Z")

    let target = try #require(data["target"] as? [String: Any])
    #expect(target["type"] as? String == "Segments")
}

@Test func rejectsInvalidRequestBeforeSending() async throws {
    let transport = FakeTransport(responses: [])
    let service = makeWorkflowService(transport)

    await #expect(throws: PushFireError.self) {
        _ = try await service.run("not-a-uuid", target: .subscribers([targetUUID]), at: nil)
    }

    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func rejectsEmptyTargetsBeforeSending() async throws {
    let transport = FakeTransport(responses: [])
    let service = makeWorkflowService(transport)

    await #expect(throws: PushFireError.self) {
        _ = try await service.run(workflowUUID, target: .subscribers([]), at: nil)
    }

    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}
