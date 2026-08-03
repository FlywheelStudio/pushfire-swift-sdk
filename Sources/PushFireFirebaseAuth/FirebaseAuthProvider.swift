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
                continuation.yield(Self.authEvent(for: user.map(Identity.init)))
            }

            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
    }

    /// The fields of a Firebase user this provider reads.
    ///
    /// `FirebaseAuth.User` has no public initialiser, so it cannot be constructed in a
    /// test. Mapping through this struct is what makes the identity logic below
    /// verifiable at all.
    struct Identity {
        let uid: String
        let displayName: String?
        let email: String?
        let phoneNumber: String?

        init(uid: String, displayName: String?, email: String?, phoneNumber: String?) {
            self.uid = uid
            self.displayName = displayName
            self.email = email
            self.phoneNumber = phoneNumber
        }

        init(_ user: User) {
            self.init(
                uid: user.uid,
                displayName: user.displayName,
                email: user.email,
                phoneNumber: user.phoneNumber
            )
        }
    }

    /// Maps a Firebase auth state change to a PushFire auth event.
    ///
    /// Extracted so it can be tested directly, mirroring
    /// `SupabaseAuthProvider.authEvent(for:session:)`: it is a pure function, and the
    /// surrounding `addStateDidChangeListener` callback cannot be unit-tested.
    ///
    /// Empty-string name, email and phone are normalised to nil by `AuthUser.init` —
    /// Firebase returns `""` rather than nil for an unset display name in some flows.
    static func authEvent(for identity: Identity?) -> AuthEvent {
        guard let identity else { return .signedOut }
        return .signedIn(
            AuthUser(
                id: identity.uid,
                name: identity.displayName,
                email: identity.email,
                phone: identity.phoneNumber
            )
        )
    }
}
