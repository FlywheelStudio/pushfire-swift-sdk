import Foundation

/// When a workflow execution should run.
public enum WorkflowExecutionType: String, Codable, Sendable {
    case immediate = "Immediate"
    case scheduled = "Scheduled"
}

/// What a workflow execution targets.
public enum WorkflowTargetType: String, Codable, Sendable {
    case subscribers = "Subscribers"
    case segments = "Segments"
}

/// The target configuration for a workflow execution.
public struct WorkflowTarget: Codable, Sendable, Equatable {
    public let type: WorkflowTargetType
    public let values: [String]

    public init(type: WorkflowTargetType, values: [String]) {
        self.type = type
        self.values = values
    }
}

/// A request to execute a workflow.
///
/// `Encodable` only, deliberately. The custom `encode(to:)` below writes `scheduledFor`
/// as an ISO-8601 string, but a synthesized `init(from:)` would read it with the decoder's
/// default date strategy (`.deferredToDate`, i.e. a Double) and fail on the very string
/// this type produces. Nothing ever decodes a request — it only travels to the server — so
/// the asymmetry is removed by dropping the direction we do not use.
public struct WorkflowExecutionRequest: Encodable, Sendable, Equatable {
    public let workflowId: String
    public let type: WorkflowExecutionType
    public let scheduledFor: Date?
    public let target: WorkflowTarget

    public init(
        workflowId: String,
        type: WorkflowExecutionType,
        scheduledFor: Date? = nil,
        target: WorkflowTarget
    ) {
        self.workflowId = workflowId
        self.type = type
        self.scheduledFor = scheduledFor
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case workflowId, type, scheduledFor, target
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workflowId, forKey: .workflowId)
        try container.encode(type, forKey: .type)
        try container.encode(target, forKey: .target)
        if let scheduledFor {
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: scheduledFor), forKey: .scheduledFor)
        }
    }

    /// Validates the request before it is sent.
    /// Mirrors `WorkflowExecutionRequest.validate()` in the Dart SDK.
    public func validate() throws {
        guard Self.isUUID(workflowId) else {
            throw PushFireError.configuration("workflowId must be a valid UUID")
        }
        if type == .scheduled && scheduledFor == nil {
            throw PushFireError.configuration(
                "scheduledFor is required when type is Scheduled"
            )
        }
        guard !target.values.isEmpty else {
            throw PushFireError.configuration("target values cannot be empty")
        }
        for value in target.values where !Self.isUUID(value) {
            throw PushFireError.configuration(
                "All target values must be valid UUIDs: \(value)"
            )
        }
    }

    private static func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

/// The server's response to a workflow execution request.
public struct WorkflowExecutionResponse: Codable, Sendable, Equatable {
    public let id: String?
    public let message: String?

    public init(id: String?, message: String?) {
        self.id = id
        self.message = message
    }
}
