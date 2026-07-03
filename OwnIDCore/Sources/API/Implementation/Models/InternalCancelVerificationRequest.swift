import Foundation

/// Request payload for canceling a challenge operation.
///
/// OpenAPI source: `CancelVerificationRequest` schema.
internal struct InternalCancelVerificationRequest: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challengeId: InternalChallengeId
    internal private(set) var reason: InternalCancelReason?

    internal init(challengeId: InternalChallengeId, reason: InternalCancelReason? = nil) {
        self.challengeId = challengeId
        self.reason = reason
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challengeId = "challengeId"
        case reason = "reason"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}
