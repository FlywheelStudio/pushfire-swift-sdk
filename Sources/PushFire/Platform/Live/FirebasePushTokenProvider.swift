import FirebaseMessaging
import Foundation

/// Token refresh is observed through `NotificationCenter`, **not** by assigning
/// `Messaging.messaging().delegate`. Assigning the delegate would silently take it from a
/// host app that has its own — an SDK must never do that.
struct FirebasePushTokenProvider: PushTokenProvider {
    func apnsToken() async -> String? {
        Messaging.messaging().apnsToken.map { token in
            token.map { String(format: "%02x", $0) }.joined()
        }
    }

    func fcmToken() async -> String? {
        do {
            return try await Messaging.messaging().token()
        } catch {
            return nil
        }
    }

    var tokenRefreshes: AsyncStream<String> {
        AsyncStream { continuation in
            // `addObserver` returns `any NSObjectProtocol`, which is not `Sendable`. The
            // token is an opaque handle that is only ever passed back to
            // `removeObserver` — Apple's contract guarantees that round-trip is safe from
            // any thread, so `nonisolated(unsafe)` here is a deliberate, narrow opt-out
            // rather than a blanket suppression.
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: .MessagingRegistrationTokenRefreshed,
                object: nil,
                queue: nil
            ) { notification in
                if let token = notification.object as? String {
                    continuation.yield(token)
                } else if let token = Messaging.messaging().fcmToken {
                    continuation.yield(token)
                }
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
