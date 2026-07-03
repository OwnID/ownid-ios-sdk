import Foundation

/// About: The user exhausted the allowed verification attempts for the challenge.
/// End-user: Ask the user to start a new challenge.
/// Developer action: Do not retry the same challenge; clear local challenge state and restart the flow.
///
/// OpenAPI source: `MaximumAttemptsReachedError` schema.
internal struct InternalMaximumAttemptsReachedErrorResponse: Sendable, Codable, Hashable {
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
