import Foundation

/// About: The submitted verification code or equivalent challenge proof is incorrect.
/// End-user: Ask the user to try again while attempts remain.
/// Developer action: Keep the current challenge active and update remaining-attempt UI if available.
///
/// OpenAPI source: `VerificationCodeWrongError` schema.
internal struct InternalVerificationCodeWrongErrorResponse: Sendable, Codable, Hashable {
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
