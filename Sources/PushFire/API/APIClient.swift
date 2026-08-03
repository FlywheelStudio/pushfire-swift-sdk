import Foundation

/// Sends requests to the PushFire API.
actor APIClient {
    private let config: PushFireConfiguration
    private let transport: any HTTPTransport
    private let logger: PushFireLogger

    init(config: PushFireConfiguration, transport: any HTTPTransport, logger: PushFireLogger) {
        self.config = config
        self.transport = transport
        self.logger = logger
    }

    /// Sends a request and decodes the response.
    func send<Body: Encodable, Response: Decodable>(
        _ endpoint: Endpoint,
        body: Body
    ) async throws -> Response {
        let data = try await perform(endpoint, body: body)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw PushFireError.api(
                message: "Could not decode the response",
                code: nil,
                statusCode: nil,
                responseBody: String(data: data, encoding: .utf8)
            )
        }
    }

    /// Sends a request and discards the response body.
    func send<Body: Encodable>(_ endpoint: Endpoint, body: Body) async throws {
        _ = try await perform(endpoint, body: body)
    }

    private func perform<Body: Encodable>(_ endpoint: Endpoint, body: Body) async throws -> Data {
        let url = config.baseURL.appendingPathComponent(endpoint.path)

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(Envelope(data: body))
        } catch {
            // Caller-supplied metadata can contain values (e.g. `JSONValue.double(.nan)`)
            // that make `JSONEncoder` throw a raw `EncodingError`. Every throwing SDK
            // call is documented to throw `PushFireError`, so that error must not
            // escape here.
            throw PushFireError.configuration(
                "Could not encode the request body: \(error.localizedDescription)"
            )
        }

        logger.apiRequest(method: endpoint.method, url: url.absoluteString, body: request.httpBody)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as PushFireError {
            throw error
        } catch {
            logger.error("Network error during \(endpoint.method) \(endpoint.path)", error)
            throw PushFireError.network(error.localizedDescription)
        }

        logger.apiResponse(
            method: endpoint.method,
            url: url.absoluteString,
            statusCode: response.statusCode,
            body: data
        )

        guard (200..<300).contains(response.statusCode) else {
            let apiError = Self.decodeError(statusCode: response.statusCode, body: data)
            // The response body above is logged at debug level and marked `.private`, so
            // without this line a shipped app gives no usable trace of a 401 or 422. The
            // message here is the server's own, already extracted, and carries no
            // credentials.
            logger.error(
                "\(endpoint.method) \(endpoint.path) failed with HTTP \(response.statusCode)",
                apiError
            )
            throw apiError
        }

        return data.isEmpty ? Data("{}".utf8) : data
    }

    /// Wraps a body in the backend's `{"data": ...}` envelope.
    private struct Envelope<T: Encodable>: Encodable {
        let data: T
    }

    /// Extracts the most useful error message the server gave us.
    ///
    /// Precedence — `message`, then `error`, then the joined `errors[].message`
    /// validation array, then the raw body, then a status fallback. This ordering
    /// exists so the caller always sees the server's actual response rather than a
    /// generic string; it mirrors the Dart client and must not regress.
    static func decodeError(statusCode: Int, body: Data) -> PushFireError {
        let raw = String(data: body, encoding: .utf8)
        var message = ""
        var code: String?

        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let value = json["message"] as? String {
                message = value
            } else if let value = json["error"] as? String {
                message = value
            } else if let joined = joinValidationErrors(json["errors"]) {
                message = joined
            } else {
                message = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            code = json["code"] as? String
        } else {
            message = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if message.isEmpty {
            message = "API request failed with status \(statusCode)"
        }

        return .api(message: message, code: code, statusCode: statusCode, responseBody: raw)
    }

    /// Joins messages from a validation-style `errors` array, e.g.
    /// `{"errors":[{"path":"data.phone","message":"Phone is required"}]}`.
    /// Returns nil when `errors` is not a non-empty array carrying messages.
    private static func joinValidationErrors(_ errors: Any?) -> String? {
        guard let list = errors as? [Any], !list.isEmpty else { return nil }
        let messages = list.compactMap { ($0 as? [String: Any])?["message"] as? String }
            .filter { !$0.isEmpty }
        return messages.isEmpty ? nil : messages.joined(separator: "; ")
    }
}
