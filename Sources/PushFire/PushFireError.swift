import Foundation

/// The system error underneath a `PushFireError`.
///
/// A snapshot rather than the error itself: `any Error` is not `Sendable`, and
/// `PushFireError` crosses actor boundaries throughout the SDK. `domain` and `code` are
/// the parts worth branching on — for a transport failure they are `NSURLErrorDomain`
/// and one of the `NSURLError*` constants.
public struct UnderlyingError: Sendable, Hashable, CustomStringConvertible {
    public let domain: String
    public let code: Int
    public let message: String

    public init(_ error: any Error) {
        let bridged = error as NSError
        self.domain = bridged.domain
        self.code = bridged.code
        self.message = bridged.localizedDescription
    }

    public var description: String { "\(domain) \(code): \(message)" }
}

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
    ///
    /// `underlying` carries the system error's domain and code so you can tell these
    /// apart without string-matching the message:
    ///
    /// ```swift
    /// catch PushFireError.network(_, let underlying) {
    ///     if underlying?.code == NSURLErrorNotConnectedToInternet { queueForLater() }
    /// }
    /// ```
    case network(String, underlying: UnderlyingError? = nil)

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
        case .network(let message, let underlying):
            guard let underlying else { return "PushFire network error: \(message)" }
            return "PushFire network error: \(message) (\(underlying.domain) \(underlying.code))"
        case .api(let message, let code, let statusCode, _):
            var text = "PushFire API error"
            if let code { text += "(\(code))" }
            if let statusCode { text += " [HTTP \(statusCode)]" }
            return text + ": \(message)"
        }
    }
}
