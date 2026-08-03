import Foundation
import Testing

@testable import PushFire

/// A `Sendable`-safe wrapper around a decoded JSON object.
///
/// `JSONSerialization` returns `[String: Any]`, and `Any` is never `Sendable`, so a
/// plain dictionary can't be returned from an actor-isolated method to a nonisolated
/// caller under Swift 6 strict concurrency. This box is `@unchecked Sendable`: it
/// holds an immutable JSON snapshot that is never mutated after being handed back,
/// so treating it as safe to share is sound even though the compiler can't prove it.
struct JSONObject: @unchecked Sendable {
    private let raw: [String: Any]

    init(_ raw: [String: Any]) {
        self.raw = raw
    }

    subscript(key: String) -> Any? {
        raw[key]
    }
}

/// Records requests and replays canned responses.
actor FakeTransport: HTTPTransport {
    struct Response: Sendable {
        let statusCode: Int
        let body: Data

        static func ok(_ json: String) -> Response {
            Response(statusCode: 200, body: Data(json.utf8))
        }

        static func failure(_ statusCode: Int, _ body: String) -> Response {
            Response(statusCode: statusCode, body: Data(body.utf8))
        }
    }

    /// Tracks `close()`, which the protocol declares nonisolated and synchronous, so it
    /// cannot touch this actor's isolated state.
    private final class ClosedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var closed = false

        var value: Bool { lock.withLock { closed } }
        func set() { lock.withLock { closed = true } }
    }

    private var queued: [Response]
    private(set) var recorded: [URLRequest] = []
    private nonisolated let closedFlag = ClosedFlag()

    /// Whether `close()` has been called. Used to prove `shutdown()` releases the session.
    nonisolated var didClose: Bool { closedFlag.value }

    init(responses: [Response]) {
        self.queued = responses
    }

    init(response: Response) {
        self.queued = [response]
    }

    nonisolated func close() {
        closedFlag.set()
    }

    nonisolated func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await record(request)
    }

    private func record(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        recorded.append(request)
        guard !queued.isEmpty else {
            throw PushFireError.network("FakeTransport ran out of queued responses")
        }
        let next = queued.removeFirst()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (next.body, http)
    }

    /// The decoded JSON body of the request at `index`.
    func requestBody(at index: Int) throws -> JSONObject {
        let data = try #require(recorded[index].httpBody)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return JSONObject(object)
    }

    /// The `data` envelope of the request at `index`.
    func requestData(at index: Int) throws -> JSONObject {
        let body = try requestBody(at: index)
        return JSONObject(body["data"] as! [String: Any])
    }
}
