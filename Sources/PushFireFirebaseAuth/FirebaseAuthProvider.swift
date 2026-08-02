import FirebaseAuth
import Foundation
import PushFire

/// Drives PushFire subscriber login and logout from Firebase Authentication.
///
/// ```swift
/// try await PushFire.configure(
///     PushFireConfiguration(apiKey: "your-api-key"),
///     authProvider: FirebaseAuthProvider()
/// )
/// ```
public struct FirebaseAuthProvider: AuthProvider {
    public init() {}

    public var events: AsyncStream<AuthEvent> {
        AsyncStream { continuation in
            nonisolated(unsafe) let handle = Auth.auth().addStateDidChangeListener { _, user in
                if let user {
                    continuation.yield(
                        .signedIn(
                            AuthUser(
                                id: user.uid,
                                name: user.displayName,
                                email: user.email,
                                phone: user.phoneNumber
                            )
                        )
                    )
                } else {
                    continuation.yield(.signedOut)
                }
            }

            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
    }
}
