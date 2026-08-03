import Foundation

/// The current notification state for this device.
public struct NotificationStatus: Sendable, Equatable {
    /// Whether the OS-level notification permission is granted.
    public let isPermissionGranted: Bool

    /// The PushFire preference set via `setNotificationEnabled`.
    /// Only meaningful when `isPermissionGranted` is true.
    public let isEnabled: Bool

    public init(isPermissionGranted: Bool, isEnabled: Bool) {
        self.isPermissionGranted = isPermissionGranted
        self.isEnabled = isEnabled
    }
}
