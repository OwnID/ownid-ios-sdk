import Foundation

internal struct InternalVerificationRequest: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challengeId: InternalChallengeId

    internal init(challengeId: InternalChallengeId) {
        self.challengeId = challengeId
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challengeId = "challengeId"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
    }
}
