import Foundation

/// About: The active challenge limit or concurrency guard was reached.
/// End-user: Ask the user to wait briefly or finish an existing challenge before starting another.
/// Developer action: Rate-limit retries, log repeated occurrences, and inspect challenge cleanup if this persists.
///
/// OpenAPI source: `MaximumChallengesReachedError` schema.
internal struct InternalMaximumChallengesReachedErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String

    internal init(errorCode: InternalErrorCode, message: String) {
        self.errorCode = errorCode
        self.message = message
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
    }
}
