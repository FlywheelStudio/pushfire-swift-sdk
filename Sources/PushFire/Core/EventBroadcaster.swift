import Foundation

/// Fans SDK events out to every observer.
actor EventBroadcaster {
    private var continuations: [UUID: AsyncStream<PushFireEvent>.Continuation] = [:]

    /// A new stream of events. Each caller gets its own.
    func stream() -> AsyncStream<PushFireEvent> {
        var captured: AsyncStream<PushFireEvent>.Continuation!
        let stream = AsyncStream<PushFireEvent> { captured = $0 }
        let continuation = captured!

        let id = UUID()
        continuations[id] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }

        return stream
    }

    /// Sends an event to every observer.
    func emit(_ event: PushFireEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Ends every stream. Called when the SDK shuts down.
    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
