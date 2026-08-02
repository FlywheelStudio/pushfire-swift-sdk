import Foundation

@testable import PushFire

/// Auth provider driven manually from tests.
final class FakeAuthProvider: AuthProvider, @unchecked Sendable {
    private let continuation: AsyncStream<AuthEvent>.Continuation
    let events: AsyncStream<AuthEvent>

    init() {
        var captured: AsyncStream<AuthEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func emit(_ event: AuthEvent) {
        continuation.yield(event)
    }
}
