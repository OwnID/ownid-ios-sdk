import Foundation

/// About: The verification code resend limit or debounce policy was reached.
/// End-user: Ask the user to wait or restart the challenge.
/// Developer action: Disable resend UI for the current challenge and respect the server resend policy.
///
/// OpenAPI source: `MaximumResendAttemptsReachedError` schema.
internal struct InternalMaximumResendAttemptsReachedErrorResponse: Sendable, Codable, Hashable {
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
