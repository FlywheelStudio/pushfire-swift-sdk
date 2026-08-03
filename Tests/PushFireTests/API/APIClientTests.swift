import Foundation
import Testing

@testable import PushFire

private struct Payload: Encodable {
    let name: String
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
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

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
