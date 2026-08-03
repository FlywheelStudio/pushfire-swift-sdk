import Foundation

/// The PushFire edge functions this SDK calls.
enum Endpoint: String, Sendable {
    case registerDevice = "register-device"
    case updateDevice = "update-device"
    case loginSubscriber = "login-subscriber"
    case updateSubscriber = "update-subscriber"
    case logoutSubscriber = "logout-subscriber"
    case addSubscriberTag = "add-subscriber-tag"
    case updateSubscriberTag = "update-subscriber-tag"
    case removeSubscriberTag = "remove-subscriber-tag"
    case createWorkflowExecution = "create-workflow-execution"

    var path: String { rawValue }

    var method: String {
        switch self {
        case .registerDevice, .loginSubscriber, .logoutSubscriber,
            .addSubscriberTag, .createWorkflowExecution:
            return "POST"
        case .updateDevice, .updateSubscriber, .updateSubscriberTag:
            return "PATCH"
        case .removeSubscriberTag:
            return "DELETE"
        }
    }
}
