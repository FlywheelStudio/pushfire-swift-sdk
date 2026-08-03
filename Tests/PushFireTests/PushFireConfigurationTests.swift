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

@Test func configurationNeverPrintsTheAPIKey() {
    let secret = "pk_live_do_not_leak_me"
    let config = PushFireConfiguration(apiKey: secret, enableLogging: true)

    // Every path an integrator might take while debugging an integration.
    var dumped = ""
    dump(config, to: &dumped)

    #expect(!String(describing: config).contains(secret))
    #expect(!String(reflecting: config).contains(secret))
    #expect(!"\(config)".contains(secret))
    #expect(!dumped.contains(secret))

    // Still useful output: the non-secret fields survive.
    #expect(String(describing: config).contains("enableLogging: true"))
}
