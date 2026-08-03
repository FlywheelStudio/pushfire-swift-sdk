import Foundation

/// Sends HTTP requests. Injected so tests can assert on exact request bodies
/// without `URLProtocol` interception.
///
/// Internal: this is a test seam, not a documented integrator extension point.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Releases any resources the transport owns. Called from `PushFireCore.shutdown()`.
    func close()
}

extension HTTPTransport {
    /// Most transports (including every test fake) own nothing that needs releasing.
    func close() {}
}

/// The live transport, backed by `URLSession`.
struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        // `timeoutIntervalForRequest` is an *inactivity* timeout: it resets on every byte
        // received, so a server that drips a response slowly can hold a request open
        // indefinitely. The Flutter SDK applies a wall-clock deadline to the whole call,
        // so `timeoutIntervalForResource` is what actually matches it.
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }

    func close() {
        // The session holds a delegate queue and retains its operation queue until
        // invalidated, so each configure/shutdown cycle would otherwise leak one.
        session.invalidateAndCancel()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PushFireError.network("Response was not an HTTP response")
        }
        return (data, http)
    }
}
