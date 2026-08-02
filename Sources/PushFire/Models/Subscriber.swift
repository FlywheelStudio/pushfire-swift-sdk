import Foundation

/// A JSON value, used for subscriber metadata where the schema is caller-defined.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// A subscriber in the PushFire system.
public struct Subscriber: Codable, Sendable, Equatable {
    public let id: String?
    public let deviceId: String?
    public let externalId: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let metadata: [String: JSONValue]?

    public init(
        id: String? = nil,
        deviceId: String? = nil,
        externalId: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.externalId = externalId
        self.name = name
        self.email = email
        self.phone = phone
        self.metadata = metadata
    }

    /// Returns a copy with the given fields replaced. Passing `nil` keeps the existing value,
    /// matching the Dart `copyWith` semantics.
    public func with(
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) -> Subscriber {
        Subscriber(
            id: id,
            deviceId: deviceId,
            externalId: externalId,
            name: name ?? self.name,
            email: email ?? self.email,
            phone: phone ?? self.phone,
            metadata: metadata ?? self.metadata
        )
    }
}
