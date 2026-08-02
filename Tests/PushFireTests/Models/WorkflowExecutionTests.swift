import Foundation
import Testing

@testable import PushFire

private let validUUID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
private let otherUUID = "550e8400-e29b-41d4-a716-446655440000"

@Test func workflowRequestEncodesEnumRawValues() throws {
    let request = WorkflowExecutionRequest(
        workflowId: validUUID,
        type: .immediate,
        target: WorkflowTarget(type: .subscribers, values: [otherUUID])
    )

    let data = try JSONEncoder().encode(request)
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(json["type"] as? String == "Immediate")
    let target = try #require(json["target"] as? [String: Any])
    #expect(target["type"] as? String == "Subscribers")
    #expect(json["scheduledFor"] == nil)
}

@Test func workflowRequestRejectsNonUUIDWorkflowID() {
    let request = WorkflowExecutionRequest(
        workflowId: "not-a-uuid",
        type: .immediate,
        target: WorkflowTarget(type: .subscribers, values: [otherUUID])
    )

    #expect(throws: PushFireError.self) { try request.validate() }
}

@Test func workflowRequestRejectsScheduledWithoutDate() {
    let request = WorkflowExecutionRequest(
        workflowId: validUUID,
        type: .scheduled,
        target: WorkflowTarget(type: .segments, values: [otherUUID])
    )

    #expect(throws: PushFireError.self) { try request.validate() }
}

@Test func workflowRequestRejectsEmptyTargets() {
    let request = WorkflowExecutionRequest(
        workflowId: validUUID,
        type: .immediate,
        target: WorkflowTarget(type: .subscribers, values: [])
    )

    #expect(throws: PushFireError.self) { try request.validate() }
}

@Test func workflowRequestAcceptsValidScheduled() throws {
    let request = WorkflowExecutionRequest(
        workflowId: validUUID,
        type: .scheduled,
        scheduledFor: Date(timeIntervalSince1970: 1_700_000_000),
        target: WorkflowTarget(type: .segments, values: [otherUUID])
    )

    try request.validate()

    let data = try JSONEncoder().encode(request)
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(json["scheduledFor"] as? String == "2023-11-14T22:13:20Z")
}
