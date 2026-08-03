import Foundation

/// Manages tags on the logged-in subscriber.
actor TagService {
    private let apiClient: APIClient
    private let subscriberService: SubscriberService
    private let logger: PushFireLogger

    init(apiClient: APIClient, subscriberService: SubscriberService, logger: PushFireLogger) {
        self.apiClient = apiClient
        self.subscriberService = subscriberService
        self.logger = logger
    }

    private struct TagBody: Encodable {
        let tagId: String
        let subscriberId: String
        let value: String?
    }

    // MARK: - Single

    @discardableResult
    func addTag(_ tagId: String, value: String) async throws -> SubscriberTag {
        try await write(.addSubscriberTag, tagId: tagId, value: value)
    }

    @discardableResult
    func updateTag(_ tagId: String, value: String) async throws -> SubscriberTag {
        try await write(.updateSubscriberTag, tagId: tagId, value: value)
    }

    func removeTag(_ tagId: String) async throws {
        _ = try await write(.removeSubscriberTag, tagId: tagId, value: nil)
    }

    // MARK: - Bulk

    /// Adds several tags. Pass an array of pairs rather than a dictionary so the order
    /// of the requests is deterministic and testable.
    func addTags(_ tags: [(String, String)]) async throws -> BulkTagResult {
        try await bulk(tags) { try await self.addTag($0, value: $1) }
    }

    func updateTags(_ tags: [(String, String)]) async throws -> BulkTagResult {
        try await bulk(tags) { try await self.updateTag($0, value: $1) }
    }

    func removeTags(_ tagIds: [String]) async throws -> BulkTagResult {
        var succeeded: [SubscriberTag] = []
        var failed: [BulkTagResult.Failure] = []

        for tagId in tagIds {
            do {
                // Go through `write` rather than `removeTag` so the successful removals
                // can be reported. Returning an empty `succeeded` would make a partial
                // failure indistinguishable from "nothing was attempted".
                succeeded.append(try await write(.removeSubscriberTag, tagId: tagId, value: nil))
            } catch {
                logger.warning("Failed to remove tag \(tagId)", error)
                failed.append(
                    BulkTagResult.Failure(tagId: tagId, message: Self.message(for: error))
                )
            }
        }

        if succeeded.isEmpty && !failed.isEmpty {
            throw PushFireError.tag(
                "Failed to remove every tag: \(failed.map(\.tagId).joined(separator: ", "))"
            )
        }

        return BulkTagResult(succeeded: succeeded, failed: failed)
    }

    // MARK: - Internals

    private func write(
        _ endpoint: Endpoint,
        tagId: String,
        value: String?
    ) async throws -> SubscriberTag {
        guard let subscriberId = await subscriberService.subscriberId() else {
            throw PushFireError.tag("No subscriber is logged in")
        }

        logger.info("\(endpoint.rawValue): \(tagId)")

        try await apiClient.send(
            endpoint,
            body: TagBody(tagId: tagId, subscriberId: subscriberId, value: value)
        )

        return SubscriberTag(tagId: tagId, subscriberId: subscriberId, value: value ?? "")
    }

    private func bulk(
        _ tags: [(String, String)],
        _ operation: (String, String) async throws -> SubscriberTag
    ) async throws -> BulkTagResult {
        var succeeded: [SubscriberTag] = []
        var failed: [BulkTagResult.Failure] = []

        for (tagId, value) in tags {
            do {
                succeeded.append(try await operation(tagId, value))
            } catch {
                logger.warning("Failed to write tag \(tagId)", error)
                failed.append(
                    BulkTagResult.Failure(tagId: tagId, message: Self.message(for: error))
                )
            }
        }

        if succeeded.isEmpty && !failed.isEmpty {
            throw PushFireError.tag(
                "Failed to write every tag: \(failed.map(\.tagId).joined(separator: ", "))"
            )
        }

        return BulkTagResult(succeeded: succeeded, failed: failed)
    }

    private static func message(for error: any Error) -> String {
        if case PushFireError.api(let message, _, _, _) = error {
            return message
        }
        if let pushFireError = error as? PushFireError {
            return pushFireError.description
        }
        return String(describing: error)
    }
}
