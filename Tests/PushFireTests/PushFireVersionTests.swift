import Testing
@testable import PushFire

@Test func sdkVersionIsSet() {
    #expect(PushFire.sdkVersion == "0.1.0")
}
