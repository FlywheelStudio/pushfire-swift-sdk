import Foundation

/// The outcome of `setNotificationEnabled`.
public enum SetNotificationResult: Sendable, Equatable {
    /// The preference was updated on the server.
    case success

    /// Notifications cannot be enabled because the OS permission is denied.
    /// The user must grant it in Settings first.
    case systemPermissionDenied
}
