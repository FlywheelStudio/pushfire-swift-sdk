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
    // Milliseconds are always present, matching Dart's toIso8601String().
    #expect(json["scheduledFor"] as? String == "2023-11-14T22:13:20.000Z")
}

@Test func workflowResponseReadsTopLevelFields() throws {
    let json = Data(#"{"id": "exec_1", "message": "queued"}"#.utf8)

    let response = try JSONDecoder().decode(WorkflowExecutionResponse.self, from: json)

    #expect(response.id == "exec_1")
    #expect(response.message == "queued")
}

@Test func workflowResponseFallsBackToNestedData() throws {
    // Both fields are optional, so before the nested probe this decoded to (nil, nil)
    // with no error — the execution id vanished silently.
    let json = Data(#"{"data": {"id": "exec_1", "message": "queued"}}"#.utf8)

    let response = try JSONDecoder().decode(WorkflowExecutionResponse.self, from: json)

    #expect(response.id == "exec_1")
    #expect(response.message == "queued")
}

@Test func workflowResponsePrefersTopLevelOverNested() throws {
    let json = Data(#"{"id": "top", "data": {"id": "nested"}}"#.utf8)

    let response = try JSONDecoder().decode(WorkflowExecutionResponse.self, from: json)

    #expect(response.id == "top")
}

@Test func workflowResponseToleratesNonObjectData() throws {
    let json = Data(#"{"id": "exec_1", "data": "not-an-object"}"#.utf8)

    let response = try JSONDecoder().decode(WorkflowExecutionResponse.self, from: json)

    #expect(response.id == "exec_1")
}

@Test func workflowResponseDecodesEmptyObject() throws {
    let response = try JSONDecoder().decode(
        WorkflowExecutionResponse.self, from: Data("{}".utf8))

    #expect(response.id == nil)
    #expect(response.message == nil)
}

@Test func workflowRequestKeepsSubSecondPrecision() throws {
    // A default ISO8601DateFormatter drops the fractional field entirely, which would
    // schedule this workflow 900 ms early.
    let request = WorkflowExecutionRequest(
        workflowId: validUUID,
        type: .scheduled,
        scheduledFor: Date(timeIntervalSince1970: 1_700_000_000.9),
        target: WorkflowTarget(type: .segments, values: [otherUUID])
    )

    try request.validate()

    let data = try JSONEncoder().encode(request)
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(json["scheduledFor"] as? String == "2023-11-14T22:13:20.900Z")
}
