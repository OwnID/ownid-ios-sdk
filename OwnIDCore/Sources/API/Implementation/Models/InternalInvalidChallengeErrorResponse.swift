import Foundation

/// About: The challenge was not found, expired or already completed.
/// End-user: Ask the user to restart the operation.
/// Developer action: Stop polling or completing this challenge ID and create a fresh challenge.
///
/// OpenAPI source: `InvalidChallengeError` schema.
internal struct InternalInvalidChallengeErrorResponse: Sendable, Codable, Hashable {
    internal private(set) var errorCode: InternalErrorCode
    /// Human-readable diagnostic message.
    internal private(set) var message: String
    internal private(set) var challengeId: InternalChallengeId

    internal init(errorCode: InternalErrorCode, message: String, challengeId: InternalChallengeId) {
        self.errorCode = errorCode
        self.message = message
        self.challengeId = challengeId
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case errorCode = "errorCode"
        case message = "message"
        case challengeId = "challengeId"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
        try container.encode(challengeId, forKey: .challengeId)
    }
}
