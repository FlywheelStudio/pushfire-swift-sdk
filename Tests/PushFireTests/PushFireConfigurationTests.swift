import Foundation
import Testing

@testable import PushFire

@Test func configurationAppliesDefaults() {
    let config = PushFireConfiguration(apiKey: "key")

    #expect(config.baseURL.absoluteString == "https://api.pushfire.app/functions/v1/")
    #expect(config.enableLogging == false)
    #expect(config.timeout == 30)
    #expect(config.requestNotificationPermission == true)
    #expect(config.registerWithoutPrompt == false)
}

@Test func configurationRejectsEmptyAPIKey() {
    let config = PushFireConfiguration(apiKey: "")

    #expect(throws: PushFireError.self) { try config.validate() }
}

@Test func configurationAcceptsNonEmptyAPIKey() throws {
    try PushFireConfiguration(apiKey: "key").validate()
}
