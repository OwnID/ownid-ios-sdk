import Foundation

internal struct InternalAssertionOptionsResponse: Sendable, Codable, Hashable {
    internal private(set) var challenge: InternalChallengeId
    /// Relying Party identifier
    internal private(set) var rpId: String
    internal private(set) var allowCredentials: [InternalPublicKeyCredentialDescriptor]?
    internal private(set) var userVerification: InternalUserVerification?
    internal private(set) var timeout: InternalTimeout?

    internal init(
        challenge: InternalChallengeId,
        rpId: String,
        allowCredentials: [InternalPublicKeyCredentialDescriptor]? = nil,
        userVerification: InternalUserVerification? = nil,
        timeout: InternalTimeout? = nil
    ) {
        self.challenge = challenge
        self.rpId = rpId
        self.allowCredentials = allowCredentials
        self.userVerification = userVerification
        self.timeout = timeout
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challenge = "challenge"
        case rpId = "rpId"
        case allowCredentials = "allowCredentials"
        case userVerification = "userVerification"
        case timeout = "timeout"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challenge, forKey: .challenge)
        try container.encode(rpId, forKey: .rpId)
        try container.encodeIfPresent(allowCredentials, forKey: .allowCredentials)
        try container.encodeIfPresent(userVerification, forKey: .userVerification)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}
