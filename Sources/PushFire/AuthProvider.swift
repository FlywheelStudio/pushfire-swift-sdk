import Foundation

/// A user from your authentication system.
public struct AuthUser: Sendable, Equatable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?

    public init(id: String, name: String? = nil, email: String? = nil, phone: String? = nil) {
        self.id = id
        // Auth systems return empty strings where they mean "unset". Normalise so the
        // SDK never sends "" to the backend as a real value.
        self.name = name?.isEmpty == true ? nil : name
        self.email = email?.isEmpty == true ? nil : email
        self.phone = phone?.isEmpty == true ? nil : phone
    }
}

/// A change in authentication state.
public enum AuthEvent: Sendable, Equatable {
    case signedIn(AuthUser)
    case signedOut
}

/// Drives automatic subscriber login and logout from your auth system.
///
/// Implementations ship as separate products: `PushFireFirebaseAuth` and
/// `PushFireSupabaseAuth`. Implement this yourself for any other auth system.
public protocol AuthProvider: Sendable {
    var events: AsyncStream<AuthEvent> { get }
}
