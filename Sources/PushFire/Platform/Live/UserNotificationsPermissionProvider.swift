import Foundation
import UIKit
import UserNotifications

struct UserNotificationsPermissionProvider: NotificationPermissionProvider {
    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization(provisional: Bool) async -> NotificationAuthorization {
        var options: UNAuthorizationOptions = [.alert, .badge, .sound]
        if provisional {
            options.insert(.provisional)
        }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        } catch {
            // Fall through — read the resulting status rather than trusting the throw.
        }

        await registerForRemoteNotifications()
        return await authorizationStatus()
    }

    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func openSettings() async -> Bool {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
        return await MainActor.run {
            guard UIApplication.shared.canOpenURL(url) else { return false }
            UIApplication.shared.open(url)
            return true
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .denied
        }
    }
}
