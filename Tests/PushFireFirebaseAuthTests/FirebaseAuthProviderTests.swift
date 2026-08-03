import Foundation
import PushFire
import Testing

@testable import PushFireFirebaseAuth

private func makeIdentity(
    uid: String = "firebase_uid_1",
    displayName: String? = "Ada Lovelace",
    email: String? = "person@example.com",
    phoneNumber: String? = "+15551234567"
) -> FirebaseAuthProvider.Identity {
    FirebaseAuthProvider.Identity(
        uid: uid,
        displayName: displayName,
        email: email,
        phoneNumber: phoneNumber
    )
}

@Suite struct FirebaseAuthProviderTests {
    @Test func signedInUserProducesSignedInEvent() {
        let event = FirebaseAuthProvider.authEvent(for: makeIdentity())

        #expect(
            event
                == .signedIn(
                    AuthUser(
                        id: "firebase_uid_1",
                        name: "Ada Lovelace",
                        email: "person@example.com",
                        phone: "+15551234567"
                    )
                ))
    }

    @Test func nilUserProducesSignedOutEvent() {
        #expect(FirebaseAuthProvider.authEvent(for: nil) == .signedOut)
    }

    @Test func uidIsPassedThroughUnchanged() {
        // Unlike Supabase, whose `User.id` is a UUID that Swift renders uppercase,
        // Firebase's uid is already an opaque string. It must not be case-folded or
        // otherwise rewritten, or the same user forks into two subscriber rows.
        let mixedCase = "AbC123xyZ_Firebase"

        let event = FirebaseAuthProvider.authEvent(for: makeIdentity(uid: mixedCase))

        guard case .signedIn(let user) = event else {
            Issue.record("Expected signedIn event")
            return
        }
        #expect(user.id == mixedCase)
    }

    @Test(arguments: ["", nil] as [String?])
    func emptyOrMissingDisplayNameNormalisesToNil(name: String?) {
        // Firebase returns "" rather than nil for an unset display name in some flows,
        // and "" must not be sent to the backend as a real value.
        let event = FirebaseAuthProvider.authEvent(for: makeIdentity(displayName: name))

        guard case .signedIn(let user) = event else {
            Issue.record("Expected signedIn event")
            return
        }
        #expect(user.name == nil)
    }

    @Test func emptyEmailAndPhoneNormaliseToNil() {
        let event = FirebaseAuthProvider.authEvent(
            for: makeIdentity(email: "", phoneNumber: ""))

        guard case .signedIn(let user) = event else {
            Issue.record("Expected signedIn event")
            return
        }
        #expect(user.email == nil)
        #expect(user.phone == nil)
    }

    @Test func missingOptionalFieldsAreCarriedAsNil() {
        let event = FirebaseAuthProvider.authEvent(
            for: makeIdentity(displayName: nil, email: nil, phoneNumber: nil))

        #expect(event == .signedIn(AuthUser(id: "firebase_uid_1")))
    }
}
