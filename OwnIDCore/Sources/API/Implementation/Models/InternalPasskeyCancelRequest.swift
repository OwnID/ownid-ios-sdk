import Foundation

internal struct InternalPasskeyCancelRequest: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challenge: InternalChallengeId
    /// The reason for canceling the operation
    internal private(set) var reason: InternalCancelReason

    internal init(challenge: InternalChallengeId, reason: InternalCancelReason) {
        self.challenge = challenge
        self.reason = reason
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challenge = "challenge"
        case reason = "reason"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challenge, forKey: .challenge)
        try container.encode(reason, forKey: .reason)
    }
}
