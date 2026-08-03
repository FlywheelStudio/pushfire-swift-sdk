import Foundation
import Testing

@testable import PushFire

@Test(.timeLimit(.minutes(1)))
func deliversToEveryConsumer() async throws {
    let broadcaster = EventBroadcaster()
    let first = await broadcaster.stream()
    let second = await broadcaster.stream()

    await broadcaster.emit(.subscriberLoggedOut)

    var firstIterator = first.makeAsyncIterator()
    var secondIterator = second.makeAsyncIterator()

    let a = await firstIterator.next()
    let b = await secondIterator.next()

    #expect(a == .subscriberLoggedOut)
    #expect(b == .subscriberLoggedOut)
}

@Test(.timeLimit(.minutes(1)))
func dropsAConsumerThatStopsListeningAndKeepsServingTheRest() async throws {
    // A consumer that walks away (a SwiftUI view disappearing, a cancelled task) must be
    // released rather than accumulating in the broadcaster for the life of the SDK, and
    // its departure must not disturb anyone still listening.
    let broadcaster = EventBroadcaster()
    let survivor = await broadcaster.stream()
    let leaver = await broadcaster.stream()

    let consuming = Task {
        for await _ in leaver {}
    }
    // Let the task suspend on the stream before cancelling it, so the cancellation
    // terminates an active consumer rather than racing the start of iteration.
    try await Task.sleep(nanoseconds: 100_000_000)
    consuming.cancel()
    await consuming.value
    // Termination hands the removal to a detached Task; give it a turn to run.
    try await Task.sleep(nanoseconds: 200_000_000)

    await broadcaster.emit(.pushTokenRefreshed("after"))

    // The remaining consumer is unaffected.
    var survivorIterator = survivor.makeAsyncIterator()
    #expect(await survivorIterator.next() == .pushTokenRefreshed("after"))

    // The departed consumer's stream is finished and receives nothing further.
    var leaverIterator = leaver.makeAsyncIterator()
    #expect(await leaverIterator.next() == nil)
}

@Test(.timeLimit(.minutes(1)))
func deliversEventsInOrder() async throws {
    let broadcaster = EventBroadcaster()
    let stream = await broadcaster.stream()

    await broadcaster.emit(.pushTokenRefreshed("one"))
    await broadcaster.emit(.pushTokenRefreshed("two"))

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == .pushTokenRefreshed("one"))
    #expect(await iterator.next() == .pushTokenRefreshed("two"))
}
