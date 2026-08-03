import Foundation

/// Who a workflow execution should target.
public enum WorkflowRunTarget: Sendable, Equatable {
    case subscribers([String])
    case segments([String])

    var wireTarget: WorkflowTarget {
        switch self {
        case .subscribers(let ids):
            return WorkflowTarget(type: .subscribers, values: ids)
        case .segments(let ids):
            return WorkflowTarget(type: .segments, values: ids)
        }
    }
}

/// Triggers workflow executions.
actor WorkflowService {
    private let apiClient: APIClient
    private let logger: PushFireLogger

    init(apiClient: APIClient, logger: PushFireLogger) {
        self.apiClient = apiClient
        self.logger = logger
    }

    /// Runs a workflow, immediately or at a scheduled time.
    @discardableResult
    func run(
        _ workflowId: String,
        target: WorkflowRunTarget,
        at date: Date?
    ) async throws -> WorkflowExecutionResponse {
        let request = WorkflowExecutionRequest(
            workflowId: workflowId,
            type: date == nil ? .immediate : .scheduled,
            scheduledFor: date,
            target: target.wireTarget
        )
        return try await createWorkflowExecution(request)
    }

    /// Sends a fully-formed workflow execution request.
    @discardableResult
    func createWorkflowExecution(
        _ request: WorkflowExecutionRequest
    ) async throws -> WorkflowExecutionResponse {
        try request.validate()
        logger.info("Creating workflow execution: \(request.workflowId)")
        return try await apiClient.send(.createWorkflowExecution, body: request)
    }
}
