import Foundation

/// A create/login response carrying a new record's identifier.
///
/// The backend is inconsistent about where the id lands, so probe the known
/// shapes in the same order the Dart client does.
struct IdentifierResponse: Decodable, Sendable {
    let id: String?
    let deviceId: String?
    let subscriberId: String?
    let data: Nested?

    struct Nested: Decodable, Sendable {
        let id: String?
        let deviceId: String?
        let subscriberId: String?
    }

    var resolvedDeviceId: String? {
        id ?? deviceId ?? data?.id ?? data?.deviceId
    }

    var resolvedSubscriberId: String? {
        id ?? subscriberId ?? data?.id ?? data?.subscriberId
    }
}
