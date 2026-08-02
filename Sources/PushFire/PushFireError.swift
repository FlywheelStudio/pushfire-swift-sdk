import Foundation

/// Every error the PushFire SDK throws.
public enum PushFireError: Error, Sendable {
    /// `PushFire.shared` was accessed before `configure` completed.
    case notInitialized

    /// Invalid configuration or invalid arguments to an SDK call.
    case configuration(String)

    /// Device registration or notification-preference failure.
    case device(String)

    /// Subscriber login, update, or logout failure.
    case subscriber(String)

    /// Tag operation failure.
    case tag(String)

    /// Transport-level failure: timeout, offline, DNS.
    case network(String)

    /// A non-2xx response from the PushFire API.
    case api(message: String, code: String?, statusCode: Int?, responseBody: String?)
}

extension PushFireError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notInitialized:
            return "PushFire SDK is not initialized. Call PushFire.configure() first."
        case .configuration(let message):
            return "PushFire configuration error: \(message)"
        case .device(let message):
            return "PushFire device error: \(message)"
        case .subscriber(let message):
            return "PushFire subscriber error: \(message)"
        case .tag(let message):
            return "PushFire tag error: \(message)"
        case .network(let message):
            return "PushFire network error: \(message)"
        case .api(let message, let code, let statusCode, _):
            var text = "PushFire API error"
            if let code { text += "(\(code))" }
            if let statusCode { text += " [HTTP \(statusCode)]" }
            return text + ": \(message)"
        }
    }
}
