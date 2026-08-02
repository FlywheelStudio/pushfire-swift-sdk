import Foundation
import os

/// Logs SDK activity through `os.Logger` when enabled in configuration.
struct PushFireLogger: Sendable {
    private let logger = Logger(subsystem: "app.pushfire.sdk", category: "PushFire")
    private let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func info(_ message: String) {
        guard enabled else { return }
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String, _ error: (any Error)? = nil) {
        guard enabled else { return }
        if let error {
            logger.warning(
                "\(message, privacy: .public): \(String(describing: error), privacy: .public)")
        } else {
            logger.warning("\(message, privacy: .public)")
        }
    }

    func error(_ message: String, _ error: (any Error)? = nil) {
        guard enabled else { return }
        if let error {
            logger.error(
                "\(message, privacy: .public): \(String(describing: error), privacy: .public)")
        } else {
            logger.error("\(message, privacy: .public)")
        }
    }

    func apiRequest(method: String, url: String, body: Data?) {
        guard enabled else { return }
        let bodyText = body.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
        logger.debug(
            "→ \(method, privacy: .public) \(url, privacy: .public) \(bodyText, privacy: .public)")
    }

    func apiResponse(method: String, url: String, statusCode: Int, body: Data) {
        guard enabled else { return }
        let bodyText = String(data: body, encoding: .utf8) ?? "<binary>"
        logger.debug(
            "← \(method, privacy: .public) \(url, privacy: .public) [\(statusCode)] \(bodyText, privacy: .public)"
        )
    }
}
