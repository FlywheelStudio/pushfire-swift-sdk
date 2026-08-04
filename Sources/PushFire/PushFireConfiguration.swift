import Foundation

/// Configuration for the PushFire SDK.
public struct PushFireConfiguration: Sendable {
    /// Project API key. Sent as `Authorization: Bearer <apiKey>`.
    public let apiKey: String

    /// Base URL for the PushFire API.
    ///
    /// A trailing slash is optional here: paths are joined with
    /// `appendingPathComponent`, which normalises either form to the same URL. It is
    /// significant in the Flutter SDK, which concatenates strings — so a base URL copied
    /// from a working Dart config will also work here, but not the other way round.
    public let baseURL: URL

    /// Emit SDK logs through `os.Logger`.
    public let enableLogging: Bool

    /// Request timeout in seconds.
    public let timeout: TimeInterval

    /// Request the notification permission during `configure`.
    public let requestNotificationPermission: Bool

    /// When `requestNotificationPermission` is false, still trigger remote-notification
    /// registration so an APNs token — and therefore an FCM token — can be obtained
    /// without showing the interruptive permission dialog.
    ///
    /// This works by requesting *provisional* authorization: the OS registers for remote
    /// notifications and delivers notifications quietly to Notification Center without a
    /// prompt. Provisional authorization is not the same as "no authorization" — the user
    /// can later be asked to keep or turn off notifications. For a truly authorization-free
    /// registration, call `UIApplication.shared.registerForRemoteNotifications()` yourself
    /// and leave this false.
    ///
    /// No effect when `requestNotificationPermission` is true.
    public let registerWithoutPrompt: Bool

    /// `UserDefaults` suite for SDK state. Pass an app-group suite to share state with a
    /// Notification Service Extension. Defaults to `UserDefaults.standard`.
    public let userDefaultsSuiteName: String?

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.pushfire.app/functions/v1/")!,
        enableLogging: Bool = false,
        timeout: TimeInterval = 30,
        requestNotificationPermission: Bool = true,
        registerWithoutPrompt: Bool = false,
        userDefaultsSuiteName: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.enableLogging = enableLogging
        self.timeout = timeout
        self.requestNotificationPermission = requestNotificationPermission
        self.registerWithoutPrompt = registerWithoutPrompt
        self.userDefaultsSuiteName = userDefaultsSuiteName
    }

    /// Throws if the configuration cannot be used.
    public func validate() throws {
        guard !apiKey.isEmpty else {
            throw PushFireError.configuration("API key is required")
        }
    }
}

// The API key must never be printable. Without these conformances the synthesized
// output of `print`, `String(describing:)`, `String(reflecting:)` and `dump` includes
// `apiKey` in full, and configurations get logged during integration debugging. The
// Flutter SDK omits it from `toString()` for the same reason.
//
// All four printing paths resolve differently — `dump` goes through `Mirror`, not
// through either string conversion — so all three conformances are needed.
extension PushFireConfiguration: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String {
        """
        PushFireConfiguration(baseURL: \(baseURL.absoluteString), \
        enableLogging: \(enableLogging), timeout: \(timeout), \
        requestNotificationPermission: \(requestNotificationPermission), \
        registerWithoutPrompt: \(registerWithoutPrompt), \
        userDefaultsSuiteName: \(userDefaultsSuiteName ?? "nil"))
        """
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "apiKey": "<redacted>",
                "baseURL": baseURL,
                "enableLogging": enableLogging,
                "timeout": timeout,
                "requestNotificationPermission": requestNotificationPermission,
                "registerWithoutPrompt": registerWithoutPrompt,
                "userDefaultsSuiteName": userDefaultsSuiteName as Any,
            ],
            displayStyle: .struct
        )
    }
}
