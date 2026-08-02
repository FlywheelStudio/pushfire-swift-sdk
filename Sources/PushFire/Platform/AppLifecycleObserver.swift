import Foundation

/// Signals when the app returns to the foreground.
protocol AppLifecycleObserver: Sendable {
    var didBecomeActive: AsyncStream<Void> { get }
}
