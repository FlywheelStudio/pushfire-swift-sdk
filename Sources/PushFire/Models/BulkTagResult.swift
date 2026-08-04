import Foundation

/// The outcome of a bulk tag operation.
///
/// Unlike the Flutter SDK, which logs failures and returns only the successes, this
/// reports both sides so a caller can react to a partial failure.
public struct BulkTagResult: Sendable, Hashable {
    /// A tag operation that did not succeed.
    public struct Failure: Sendable, Hashable {
        public let tagId: String
        public let message: String
    }

    /// The operations that succeeded.
    ///
    /// For removals the `value` is empty — a removed tag no longer has one. The `tagId`
    /// is the meaningful field there.
    public let succeeded: [SubscriberTag]
    public let failed: [Failure]

    public init(succeeded: [SubscriberTag], failed: [Failure]) {
        self.succeeded = succeeded
        self.failed = failed
    }

    /// Whether every operation in the batch succeeded.
    public var isCompleteSuccess: Bool { failed.isEmpty }
}
