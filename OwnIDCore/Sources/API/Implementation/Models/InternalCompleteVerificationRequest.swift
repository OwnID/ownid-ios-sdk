import Foundation

internal struct InternalCompleteVerificationRequest: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challengeId: InternalChallengeId
    internal private(set) var code: String

    internal init(challengeId: InternalChallengeId, code: String) {
        self.challengeId = challengeId
        self.code = code
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challengeId = "challengeId"
        case code = "code"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(code, forKey: .code)
    }
}
