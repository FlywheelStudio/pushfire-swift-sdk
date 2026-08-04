import Foundation

/// A JSON value, used for subscriber metadata where the schema is caller-defined.
public enum JSONValue: Codable, Sendable, Hashable {
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

    // Equality and hashing are hand-written for one reason: `Double`. Synthesised
    // conformance inherits IEEE semantics, where NaN != NaN, so a `Subscriber` whose
    // metadata held a NaN could be inserted into a `Set` twice and then not be found by
    // `contains` — defeating the point of `Hashable`. NaN is reachable caller input:
    // `APIClient` explicitly defends against `JSONValue.double(.nan)` at encode time.
    //
    // Here two NaNs are equal to each other, and -0.0 is normalised to 0.0 so that
    // equal values hash equally. JSON cannot represent either value anyway, so nothing
    // that survives a round trip through the API is affected.
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return Self.doublesEqual(a, b)
        case (.bool(let a), .bool(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .int(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .double(let value):
            hasher.combine(2)
            hasher.combine(Self.hashKey(value))
        case .bool(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .array(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .object(let value):
            hasher.combine(5)
            hasher.combine(value)
        case .null:
            hasher.combine(6)
        }
    }

    /// NaN is equal to itself here, unlike IEEE equality, so that a value can be found
    /// again in the `Set` it was put into.
    private static func doublesEqual(_ a: Double, _ b: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        return a == b
    }

    /// The bit pattern to hash, with every NaN collapsed onto one and -0.0 onto 0.0, so
    /// that values `doublesEqual` calls equal always hash equally.
    private static func hashKey(_ value: Double) -> UInt64 {
        if value.isNaN { return Double.nan.bitPattern }
        return value == 0 ? 0 : value.bitPattern
    }
}

/// A subscriber in the PushFire system.
public struct Subscriber: Codable, Sendable, Hashable {
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
