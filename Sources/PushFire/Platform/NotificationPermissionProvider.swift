import Foundation

/// The OS-level notification authorization state.
enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    /// Whether notifications can be delivered.
    ///
    /// `provisional` counts as enabled because it delivers quietly to Notification
    /// Center. This matches the Dart SDK, which treats authorized and provisional
    /// alike. `ephemeral` (App Clips) does not, also matching the Dart.
    var isEnabled: Bool {
        self == .authorized || self == .provisional
    }
}

/// Reads and requests the notification permission.
protocol NotificationPermissionProvider: Sendable {
    func authorizationStatus() async -> NotificationAuthorization

    /// Requests authorization. When `provisional` is true, requests quiet
    /// authorization that shows no prompt.
    func requestAuthorization(provisional: Bool) async -> NotificationAuthorization

    /// Registers with APNs so a device token can be delivered.
    func registerForRemoteNotifications() async

    /// Opens this app's page in Settings. Returns whether it opened.
    func openSettings() async -> Bool
}
