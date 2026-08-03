import Foundation

/// Supplies the push token registered with PushFire.
///
/// The SDK ships a FirebaseMessaging-backed implementation. Provide your own to
/// `PushFire.configure` if you need custom token acquisition.
public protocol PushTokenProvider: Sendable {
    /// The APNs token, or nil if Apple has not delivered it yet.
    func apnsToken() async -> String?

    /// The FCM token, or nil if one is not available yet.
    func fcmToken() async -> String?

    /// Emits whenever the FCM token is rotated.
    var tokenRefreshes: AsyncStream<String> { get }
}
