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
func deliversEventsInOrder() async throws {
    let broadcaster = EventBroadcaster()
    let stream = await broadcaster.stream()

    await broadcaster.emit(.pushTokenRefreshed("one"))
    await broadcaster.emit(.pushTokenRefreshed("two"))

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == .pushTokenRefreshed("one"))
    #expect(await iterator.next() == .pushTokenRefreshed("two"))
}
