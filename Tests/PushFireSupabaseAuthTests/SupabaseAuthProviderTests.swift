import Foundation
import PushFire
import Supabase
import Testing

@testable import PushFireSupabaseAuth

private func makeUser(
    id: UUID = UUID(),
    email: String? = "person@example.com",
    phone: String? = "+15551234567",
    fullName: String? = "Ada Lovelace"
) -> User {
    var userMetadata: [String: AnyJSON] = [:]
    if let fullName {
        userMetadata["full_name"] = .string(fullName)
    }
    return User(
        id: id,
        appMetadata: [:],
        userMetadata: userMetadata,
        aud: "authenticated",
        email: email,
        phone: phone,
        createdAt: Date(),
        updatedAt: Date()
    )
}

private func makeSession(user: User) -> Session {
    Session(
        accessToken: "access-token",
        tokenType: "bearer",
        expiresIn: 3600,
        expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970,
        refreshToken: "refresh-token",
        user: user
    )
}

@Suite struct SupabaseAuthProviderTests {
    @Test func signedInWithSessionProducesSignedInEvent() {
        let user = makeUser()
        let session = makeSession(user: user)

        let event = SupabaseAuthProvider.authEvent(for: .signedIn, session: session)

        #expect(
            event
                == .signedIn(
                    AuthUser(
                        id: user.id.uuidString.lowercased(),
                        name: "Ada Lovelace",
                        email: "person@example.com",
                        phone: "+15551234567"
                    )
                ))
    }

    @Test func initialSessionWithSessionProducesSignedInEvent() {
        let user = makeUser()
        let session = makeSession(user: user)

        let event = SupabaseAuthProvider.authEvent(for: .initialSession, session: session)

        #expect(
            event
                == .signedIn(
                    AuthUser(
                        id: user.id.uuidString.lowercased(),
                        name: "Ada Lovelace",
                        email: "person@example.com",
                        phone: "+15551234567"
                    )
                ))
    }

    @Test func userUpdatedWithSessionProducesSignedInEvent() {
        let user = makeUser()
        let session = makeSession(user: user)

        let event = SupabaseAuthProvider.authEvent(for: .userUpdated, session: session)

        #expect(
            event
                == .signedIn(
                    AuthUser(
                        id: user.id.uuidString.lowercased(),
                        name: "Ada Lovelace",
                        email: "person@example.com",
                        phone: "+15551234567"
                    )
                ))
    }

    @Test(arguments: [AuthChangeEvent.signedIn, .initialSession, .userUpdated])
    func identityEventsWithNilSessionProduceNoEvent(event: AuthChangeEvent) {
        #expect(SupabaseAuthProvider.authEvent(for: event, session: nil) == nil)
    }

    @Test func signedOutProducesSignedOutEvent() {
        #expect(SupabaseAuthProvider.authEvent(for: .signedOut, session: nil) == .signedOut)
    }

    @Test func unmappedEventProducesNoEvent() {
        let user = makeUser()
        let session = makeSession(user: user)

        #expect(SupabaseAuthProvider.authEvent(for: .passwordRecovery, session: session) == nil)
    }

    @Test func signedInEmitsLowercasedId() {
        // supabase-swift types `User.id` as `UUID`, and `UUID.uuidString` renders
        // uppercase. The Flutter SDK sends the raw (lowercase) `sub` claim, and the
        // backend compares `externalId` as case-sensitive text, so this must be
        // lowercased or the same Supabase user forks into two subscriber rows.
        let id = UUID(uuidString: "3F8E1C2A-1234-4ABC-8DEF-0123456789AB")!
        let user = makeUser(id: id)
        let session = makeSession(user: user)

        let event = SupabaseAuthProvider.authEvent(for: .signedIn, session: session)

        guard case .signedIn(let authUser) = event else {
            Issue.record("Expected signedIn event")
            return
        }
        #expect(authUser.id == "3f8e1c2a-1234-4abc-8def-0123456789ab")
    }

    @Test func emptyEmailNormalisesToNil() {
        let user = makeUser(email: "", fullName: nil)
        let session = makeSession(user: user)

        let event = SupabaseAuthProvider.authEvent(for: .signedIn, session: session)

        guard case .signedIn(let authUser) = event else {
            Issue.record("Expected signedIn event")
            return
        }
        #expect(authUser.email == nil)
    }
}
