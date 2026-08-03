import Foundation
import PushFire
import Supabase

/// Drives PushFire subscriber login and logout from Supabase Auth.
///
/// ```swift
/// try await PushFire.configure(
///     PushFireConfiguration(apiKey: "your-api-key"),
///     authProvider: SupabaseAuthProvider(client: supabase)
/// )
/// ```
public struct SupabaseAuthProvider: AuthProvider {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public var events: AsyncStream<AuthEvent> {
        let client = self.client
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    guard let authEvent = Self.authEvent(for: event, session: session) else {
                        continue
                    }
                    continuation.yield(authEvent)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Maps a Supabase auth change to a PushFire auth event.
    ///
    /// Extracted so it can be tested directly: it is a pure function, and the
    /// surrounding `authStateChanges` loop cannot be unit-tested.
    static func authEvent(for event: AuthChangeEvent, session: Session?) -> AuthEvent? {
        switch event {
        case .signedIn, .initialSession, .userUpdated:
            guard let user = session?.user else { return nil }
            return .signedIn(
                AuthUser(
                    // `UUID.uuidString` is uppercase, but the Flutter SDK sends Supabase's
                    // raw `sub` claim, which is lowercase. The backend compares
                    // `externalId` as case-sensitive text, so mismatched case here would
                    // fork the same Supabase user into two different subscriber rows
                    // depending on which SDK logged them in.
                    id: user.id.uuidString.lowercased(),
                    name: user.userMetadata["full_name"]?.stringValue,
                    email: user.email,
                    phone: user.phone
                )
            )
        case .signedOut:
            return .signedOut
        default:
            // Other events (token refresh, password recovery, MFA) carry no
            // subscriber-identity change, so they are deliberately ignored.
            return nil
        }
    }
}
