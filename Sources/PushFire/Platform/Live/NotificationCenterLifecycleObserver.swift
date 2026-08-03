import Foundation
import UIKit

struct NotificationCenterLifecycleObserver: AppLifecycleObserver {
    var didBecomeActive: AsyncStream<Void> {
        AsyncStream { continuation in
            // See the matching comment in FirebasePushTokenProvider: the observer token
            // is not `Sendable`, but it is only ever passed back to `removeObserver`,
            // which Apple guarantees is safe from any thread.
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
