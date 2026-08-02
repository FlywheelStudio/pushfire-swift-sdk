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
                    switch event {
                    case .signedIn, .initialSession, .userUpdated:
                        guard let user = session?.user else { continue }
                        let name = user.userMetadata["full_name"]?.stringValue
                        continuation.yield(
                            .signedIn(
                                AuthUser(
                                    id: user.id.uuidString,
                                    name: name,
                                    email: user.email,
                                    phone: user.phone
                                )
                            )
                        )
                    case .signedOut:
                        continuation.yield(.signedOut)
                    default:
                        continue
                    }
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
