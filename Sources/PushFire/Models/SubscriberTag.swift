import Foundation

/// A tag associated with a subscriber.
public struct SubscriberTag: Codable, Sendable, Hashable {
    public let tagId: String
    public let subscriberId: String
    public let value: String

    public init(tagId: String, subscriberId: String, value: String) {
        self.tagId = tagId
        self.subscriberId = subscriberId
        self.value = value
    }
}
