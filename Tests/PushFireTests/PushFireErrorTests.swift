import Foundation
import Testing

@testable import PushFire

// `description` is what an app prints, logs, and reports to its crash reporter — and
// what `TagService` lifts into a bulk-failure message — so the wording of every case
// is part of the SDK's surface.

@Test func errorDescriptionsNameTheirCategory() {
    #expect(
        PushFireError.notInitialized.description
            == "PushFire SDK is not initialized. Call PushFire.configure() first."
    )
    #expect(
        PushFireError.configuration("bad key").description
            == "PushFire configuration error: bad key"
    )
    #expect(PushFireError.device("no token").description == "PushFire device error: no token")
    #expect(
        PushFireError.subscriber("not logged in").description
            == "PushFire subscriber error: not logged in"
    )
    #expect(PushFireError.tag("unknown tag").description == "PushFire tag error: unknown tag")
    #expect(PushFireError.network("offline").description == "PushFire network error: offline")
}

@Test func networkErrorDescriptionNamesTheSystemErrorWhenPresent() {
    let offline = NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorNotConnectedToInternet,
        userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
    )
    let error = PushFireError.network("offline", underlying: UnderlyingError(offline))

    #expect(
        error.description
            == "PushFire network error: offline (\(NSURLErrorDomain) \(NSURLErrorNotConnectedToInternet))"
    )
}

@Test func underlyingErrorCapturesTheDomainAndCodeToBranchOn() {
    // The point of the type: distinguishing offline from timeout without matching on
    // a localized, user-facing string.
    let timeout = URLError(.timedOut)
    let captured = UnderlyingError(timeout)

    #expect(captured.domain == NSURLErrorDomain)
    #expect(captured.code == NSURLErrorTimedOut)
    #expect(!captured.message.isEmpty)
    #expect(captured.description.contains("\(NSURLErrorTimedOut)"))
}

@Test func apiErrorDescriptionIncludesCodeAndStatusWhenPresent() {
    let full = PushFireError.api(
        message: "Bad thing",
        code: "E_BAD",
        statusCode: 400,
        responseBody: #"{"message":"Bad thing"}"#
    )
    #expect(full.description == "PushFire API error(E_BAD) [HTTP 400]: Bad thing")

    // Each optional is dropped independently rather than printing "nil".
    let noCode = PushFireError.api(
        message: "Bad thing", code: nil, statusCode: 400, responseBody: nil
    )
    #expect(noCode.description == "PushFire API error [HTTP 400]: Bad thing")

    let noStatus = PushFireError.api(
        message: "Could not decode the response", code: nil, statusCode: nil, responseBody: nil
    )
    #expect(noStatus.description == "PushFire API error: Could not decode the response")
}
