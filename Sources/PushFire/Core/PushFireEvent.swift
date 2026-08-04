import Foundation

/// Something the SDK did that an app may want to observe.
public enum PushFireEvent: Sendable, Hashable {
    /// The device was registered or updated on the server.
    case deviceRegistered(Device)

    /// A subscriber was logged in.
    case subscriberLoggedIn(Subscriber)

    /// The subscriber was logged out.
    case subscriberLoggedOut

    /// FCM rotated the push token.
    case pushTokenRefreshed(String)
}
