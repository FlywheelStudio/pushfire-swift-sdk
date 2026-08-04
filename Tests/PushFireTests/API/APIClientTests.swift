import Foundation
import Testing

@testable import PushFire

private struct Payload: Encodable {
    let name: String
}

/// Transport that fails the way `URLSession` does when the device is offline.
private struct ThrowingTransport: HTTPTransport {
    let error: any Error

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

@Test func networkFailuresCarryTheSystemErrorForBranching() async throws {
    let client = APIClient(
        config: PushFireConfiguration(apiKey: "k"),
        transport: ThrowingTransport(error: URLError(.notConnectedToInternet)),
        logger: PushFireLogger(enabled: false)
    )

    do {
        try await client.send(.registerDevice, body: Payload(name: "Jane"))
        Issue.record("expected the transport failure to surface")
    } catch let error as PushFireError {
        guard case .network(_, let underlying) = error else {
            Issue.record("expected .network, got \(error)")
            return
        }
        // Without this a caller has to string-match a localized message to tell
        // "no connection" from "timed out" and decide whether to queue or retry.
        #expect(underlying?.domain == NSURLErrorDomain)
        #expect(underlying?.code == NSURLErrorNotConnectedToInternet)
    }
}

@Test func timeoutsAreDistinguishableFromBeingOffline() async throws {
    let client = APIClient(
        config: PushFireConfiguration(apiKey: "k"),
        transport: ThrowingTransport(error: URLError(.timedOut)),
        logger: PushFireLogger(enabled: false)
    )

    do {
        try await client.send(.registerDevice, body: Payload(name: "Jane"))
        Issue.record("expected the transport failure to surface")
    } catch let error as PushFireError {
        guard case .network(_, let underlying) = error else {
            Issue.record("expected .network, got \(error)")
            return
        }
        #expect(underlying?.code == NSURLErrorTimedOut)
    }
}

@Test func encodingFailuresCarryTheSystemError() async throws {
    // Reachable from caller-supplied metadata: JSONEncoder rejects a non-finite double.
    let transport = FakeTransport(responses: [])
    let client = makeClient(transport)

    do {
        try await client.send(
            .loginSubscriber,
            body: ["score": JSONValue.double(.nan)]
        )
        Issue.record("expected the encode failure to surface")
    } catch let error as PushFireError {
        guard case .configuration(let message, let underlying) = error else {
            Issue.record("expected .configuration, got \(error)")
            return
        }
        #expect(message.contains("Could not encode the request body"))
        // Dart keeps the original object here; this keeps what can be acted on rather
        // than flattening the EncodingError into a string.
        #expect(underlying != nil)
    }

    // Nothing was sent: the failure happens before the transport is touched.
    let recorded = await transport.recorded
    #expect(recorded.isEmpty)
}

@Test func errorsRenderThroughLocalizedDescription() {
    // `localizedDescription` is what most Swift code reaches for and what lands in a
    // crash reporter. Without LocalizedError it renders as
    // "The operation couldn't be completed. (PushFire.PushFireError error N.)",
    // discarding every message the SDK builds.
    let error = PushFireError.device("no token")

    #expect(error.localizedDescription == "PushFire device error: no token")
    #expect(!error.localizedDescription.contains("couldn't be completed"))
}

private func makeClient(_ transport: FakeTransport) -> APIClient {
    APIClient(
        config: PushFireConfiguration(apiKey: "test-key"),
        transport: transport,
        logger: PushFireLogger(enabled: false)
    )
}

@Test func wrapsBodyInDataEnvelopeAndSetsHeaders() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"x"}"#))
    let client = makeClient(transport)

    try await client.send(.registerDevice, body: Payload(name: "Jane"))

    let request = await transport.recorded[0]
    #expect(request.httpMethod == "POST")
    #expect(
        request.url?.absoluteString
            == "https://api.pushfire.app/functions/v1/register-device"
    )
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    // Charset included: the Dart SDK's http client appends it for a String body, and
    // both SDKs must put the same bytes on the wire.
    #expect(
        request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8"
    )

    let data = try await transport.requestData(at: 0)
    #expect(data["name"] as? String == "Jane")
}

@Test func usesEndpointHTTPMethod() async throws {
    let transport = FakeTransport(responses: [.ok("{}"), .ok("{}")])
    let client = makeClient(transport)

    try await client.send(.updateDevice, body: Payload(name: "a"))
    try await client.send(.removeSubscriberTag, body: Payload(name: "b"))

    let recorded = await transport.recorded
    #expect(recorded[0].httpMethod == "PATCH")
    #expect(recorded[1].httpMethod == "DELETE")
}

@Test func prefersMessageFieldOnError() async throws {
    let transport = FakeTransport(
        response: .failure(400, #"{"message":"Bad thing","code":"E_BAD"}"#)
    )

    do {
        try await makeClient(transport).send(.registerDevice, body: Payload(name: "x"))
        Issue.record("expected a throw")
    } catch PushFireError.api(let message, let code, let statusCode, _) {
        #expect(message == "Bad thing")
        #expect(code == "E_BAD")
        #expect(statusCode == 400)
    }
}

@Test func fallsBackToErrorField() async throws {
    let transport = FakeTransport(response: .failure(500, #"{"error":"boom"}"#))

    do {
        try await makeClient(transport).send(.registerDevice, body: Payload(name: "x"))
        Issue.record("expected a throw")
    } catch PushFireError.api(let message, _, _, _) {
        #expect(message == "boom")
    }
}

@Test func joinsValidationErrorsArray() async throws {
    let body =
        #"{"errors":[{"path":"data.phone","message":"Phone is required"},"#
        + #"{"path":"data.email","message":"Email is invalid"}]}"#
    let transport = FakeTransport(response: .failure(422, body))

    do {
        try await makeClient(transport).send(.registerDevice, body: Payload(name: "x"))
        Issue.record("expected a throw")
    } catch PushFireError.api(let message, _, _, _) {
        #expect(message == "Phone is required; Email is invalid")
    }
}

@Test func fallsBackToRawBodyForNonJSON() async throws {
    let transport = FakeTransport(response: .failure(502, "<html>Bad Gateway</html>"))

    do {
        try await makeClient(transport).send(.registerDevice, body: Payload(name: "x"))
        Issue.record("expected a throw")
    } catch PushFireError.api(let message, _, let statusCode, _) {
        #expect(message == "<html>Bad Gateway</html>")
        #expect(statusCode == 502)
    }
}

@Test func fallsBackToStatusMessageForEmptyBody() async throws {
    let transport = FakeTransport(response: .failure(503, ""))

    do {
        try await makeClient(transport).send(.registerDevice, body: Payload(name: "x"))
        Issue.record("expected a throw")
    } catch PushFireError.api(let message, _, _, _) {
        #expect(message == "API request failed with status 503")
    }
}

@Test func decodesTypedResponse() async throws {
    let transport = FakeTransport(response: .ok(#"{"id":"dev_9"}"#))

    struct Result: Decodable { let id: String }
    let result: Result = try await makeClient(transport)
        .send(.registerDevice, body: Payload(name: "x"))

    #expect(result.id == "dev_9")
}

@Test func undecodableSuccessBodyThrowsAPIErrorCarryingTheRawBody() async throws {
    // A 2xx whose body does not match the expected type must surface as a PushFireError
    // carrying the server's actual response — a bare DecodingError escaping here would
    // break the documented "every throwing call throws PushFireError" contract and give
    // the caller nothing to debug with.
    let transport = FakeTransport(response: .ok(#"{"id":{"nested":true}}"#))

    struct Result: Decodable { let id: String }

    do {
        let _: Result = try await makeClient(transport)
            .send(.registerDevice, body: Payload(name: "x"))
        Issue.record("expected a throw")
    } catch PushFireError.api(let message, let code, let statusCode, let responseBody) {
        #expect(message == "Could not decode the response")
        #expect(code == nil)
        // The status the server actually sent. Reporting nil here would make a 200
        // carrying an HTML gateway page indistinguishable from a 204, and reads as
        // though no HTTP response arrived at all.
        #expect(statusCode == 200)
        #expect(responseBody == #"{"id":{"nested":true}}"#)
    }
}

@Test func emptySuccessBodyDecodesAsAnEmptyObject() async throws {
    // A 204-style empty body is substituted with `{}` so a response type whose fields
    // are all optional still decodes rather than failing.
    let transport = FakeTransport(response: .ok(""))

    struct Result: Decodable { let id: String? }
    let result: Result = try await makeClient(transport)
        .send(.registerDevice, body: Payload(name: "x"))

    #expect(result.id == nil)
}

// MARK: - Error-shape precedence
//
// `decodeError` is exercised directly here: the shapes below are about what the
// function extracts from a body, not about the request that produced it.

@Test func errorFallsBackToRawBodyForJSONWithoutAKnownErrorField() {
    // A JSON object the SDK does not recognise still has to hand the caller the
    // server's own words rather than a generic "request failed" string.
    let body = Data(#"{"detail":"tenant suspended","code":"E_TENANT"}"#.utf8)

    let error = APIClient.decodeError(statusCode: 403, body: body)

    guard case PushFireError.api(let message, let code, let statusCode, _) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == #"{"detail":"tenant suspended","code":"E_TENANT"}"#)
    // `code` is read independently of the message, so it survives the fallback.
    #expect(code == "E_TENANT")
    #expect(statusCode == 403)
}

@Test func errorIgnoresAnEmptyValidationErrorsArray() {
    // `errors: []` carries no message, so the chain must fall through to the raw body
    // instead of reporting an empty string.
    let error = APIClient.decodeError(statusCode: 422, body: Data(#"{"errors":[]}"#.utf8))

    guard case PushFireError.api(let message, _, _, _) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == #"{"errors":[]}"#)
}

@Test func errorIgnoresValidationEntriesWithoutMessages() {
    let body = Data(#"{"errors":[{"path":"data.phone"}]}"#.utf8)

    let error = APIClient.decodeError(statusCode: 422, body: body)

    guard case PushFireError.api(let message, _, _, _) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == #"{"errors":[{"path":"data.phone"}]}"#)
}

@Test func errorMessageWinsOverBothErrorAndValidationArray() {
    // The precedence chain mirrors the Dart client and must not regress.
    let body = Data(
        #"{"message":"top","error":"middle","errors":[{"message":"bottom"}]}"#.utf8
    )

    let error = APIClient.decodeError(statusCode: 400, body: body)

    guard case PushFireError.api(let message, _, _, _) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == "top")
}

@Test func errorFieldWinsOverTheValidationArray() {
    let body = Data(#"{"error":"middle","errors":[{"message":"bottom"}]}"#.utf8)

    let error = APIClient.decodeError(statusCode: 400, body: body)

    guard case PushFireError.api(let message, _, _, _) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == "middle")
}

@Test func errorFallsBackToStatusForABodyThatIsNotUTF8() {
    // A proxy or a misconfigured gateway can return bytes that are not UTF-8 at all.
    // There is nothing quotable in them, so the caller gets the status message rather
    // than an empty error.
    let error = APIClient.decodeError(statusCode: 502, body: Data([0xFF, 0xFE, 0xFD]))

    guard case PushFireError.api(let message, _, let statusCode, let responseBody) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == "API request failed with status 502")
    #expect(statusCode == 502)
    #expect(responseBody == nil)
}

@Test func errorFallsBackToStatusForParseableJSONThatIsNotUTF8() throws {
    // JSONSerialization also accepts UTF-16, so a body can parse as JSON while still
    // having no UTF-8 text to quote. The raw-body fallback must cope with that instead
    // of reporting an empty message.
    let body = try #require(#"{"detail":"suspended"}"#.data(using: .utf16))

    let error = APIClient.decodeError(statusCode: 403, body: body)

    guard case PushFireError.api(let message, _, _, let responseBody) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == "API request failed with status 403")
    #expect(responseBody == nil)
}

@Test func errorFallsBackToStatusForAWhitespaceOnlyBody() {
    let error = APIClient.decodeError(statusCode: 500, body: Data("   \n".utf8))

    guard case PushFireError.api(let message, _, _, let responseBody) = error else {
        Issue.record("expected an api error")
        return
    }
    #expect(message == "API request failed with status 500")
    // The untrimmed body is still handed back for diagnostics.
    #expect(responseBody == "   \n")
}
