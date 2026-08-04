import Foundation

/// Every error the PushFire SDK throws.
public enum PushFireError: Error, Sendable {
    /// The system error underneath a `PushFireError`.
    ///
    /// A snapshot rather than the error itself: `any Error` is not `Sendable`, and
    /// `PushFireError` crosses actor boundaries throughout the SDK. `domain` and `code`
    /// are the parts worth branching on — for a transport failure they are
    /// `NSURLErrorDomain` and one of the `NSURLError*` constants.
    ///
    /// Nested inside `PushFireError` rather than sitting at the top level because the
    /// module also exports a `PushFire` class, which shadows the module name: a consumer
    /// with their own `UnderlyingError` could not have written `PushFire.UnderlyingError`
    /// to disambiguate.
    ///
    /// Always check `domain` before branching on `code`. The two are only meaningful for
    /// an error that has an `NSError` representation, which every `URLSession` failure
    /// does. A plain Swift error thrown by a custom `HTTPTransport` bridges to a domain
    /// naming its type and a `code` that is a runtime layout detail, not a stable
    /// identifier.
    ///
    /// `userInfo` is not carried, so a chained `NSUnderlyingErrorKey` — the nested
    /// `NSOSStatusErrorDomain` error behind a TLS failure, for instance — is lost. When
    /// you need that depth, log the error at the call site instead.
    public struct Underlying: Sendable, Hashable, CustomStringConvertible {
        public let domain: String
        public let code: Int
        public let message: String

        public init(_ error: any Error) {
            let bridged = error as NSError
            self.domain = bridged.domain
            self.code = bridged.code
            self.message = bridged.localizedDescription
        }

        /// Builds one directly, for tests and for callers wrapping their own transport.
        public init(domain: String, code: Int, message: String) {
            self.domain = domain
            self.code = code
            self.message = message
        }

        public var description: String { "\(domain) \(code): \(message)" }
    }

    /// `PushFire.shared` was accessed before `configure` completed.
    case notInitialized

    /// Invalid configuration or invalid arguments to an SDK call.
    ///
    /// `underlying` is populated only when the failure came from the system — encoding
    /// caller-supplied `metadata` that `JSONEncoder` rejects, for instance. It is nil for
    /// the SDK's own validation.
    case configuration(String, underlying: Underlying? = nil)

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
    /// do {
    ///     try await PushFire.shared.login(externalId: "user_123")
    /// } catch PushFireError.network(_, let underlying) {
    ///     if underlying?.code == NSURLErrorNotConnectedToInternet { queueForLater() }
    /// }
    /// ```
    case network(String, underlying: Underlying? = nil)

    /// A non-2xx response from the PushFire API, or a 2xx whose body could not be
    /// decoded.
    case api(message: String, code: String?, statusCode: Int?, responseBody: String?)
}

extension PushFireError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notInitialized:
            return "PushFire SDK is not initialized. Call PushFire.configure() first."
        case .configuration(let message, let underlying):
            return Self.describe("PushFire configuration error", message, underlying)
        case .device(let message):
            return "PushFire device error: \(message)"
        case .subscriber(let message):
            return "PushFire subscriber error: \(message)"
        case .tag(let message):
            return "PushFire tag error: \(message)"
        case .network(let message, let underlying):
            return Self.describe("PushFire network error", message, underlying)
        case .api(let message, let code, let statusCode, _):
            var text = "PushFire API error"
            if let code { text += "(\(code))" }
            if let statusCode { text += " [HTTP \(statusCode)]" }
            return text + ": \(message)"
        }
    }

    private static func describe(
        _ prefix: String,
        _ message: String,
        _ underlying: Underlying?
    ) -> String {
        guard let underlying else { return "\(prefix): \(message)" }
        return "\(prefix): \(message) (\(underlying.domain) \(underlying.code))"
    }
}

// Without this, `error.localizedDescription` — the property most Swift code reaches for,
// and the one that reaches crash reporters — renders as
// "The operation couldn't be completed. (PushFire.PushFireError error 5.)", discarding
// every message above.
extension PushFireError: LocalizedError {
    public var errorDescription: String? { description }
}
