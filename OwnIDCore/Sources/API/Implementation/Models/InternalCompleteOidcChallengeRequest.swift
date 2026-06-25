import Foundation

internal struct InternalCompleteOidcChallengeRequest: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challengeId: InternalChallengeId
    /// The authorization code returned by the OIDC provider
    internal private(set) var code: String?
    /// The ID token returned by the OIDC provider
    internal private(set) var idToken: String?

    internal init(challengeId: InternalChallengeId, code: String? = nil, idToken: String? = nil) {
        self.challengeId = challengeId
        self.code = code
        self.idToken = idToken
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challengeId = "challengeId"
        case code = "code"
        case idToken = "idToken"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try container.decode(InternalChallengeId.self, forKey: .challengeId)
        self.code = try container.decodeIfPresent(String.self, forKey: .code)
        self.idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        guard (code != nil) != (idToken != nil) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Exactly one of code or idToken must be present.")
            )
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard (code != nil) != (idToken != nil) else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: container.codingPath, debugDescription: "Exactly one of code or idToken must be present.")
            )
        }
        try container.encode(challengeId, forKey: .challengeId)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(idToken, forKey: .idToken)
    }
}
