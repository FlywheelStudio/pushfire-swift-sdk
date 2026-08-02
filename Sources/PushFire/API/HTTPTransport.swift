import Foundation

/// Sends HTTP requests. Injected so tests can assert on exact request bodies
/// without `URLProtocol` interception.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The live transport, backed by `URLSession`.
struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PushFireError.network("Response was not an HTTP response")
        }
        return (data, http)
    }
}
