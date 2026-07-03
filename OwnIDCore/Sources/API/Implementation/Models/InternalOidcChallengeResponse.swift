import Foundation

internal struct InternalOidcChallengeResponse: Sendable, Codable, Hashable {
    /// The challenge's identifier
    internal private(set) var challengeId: InternalChallengeId
    /// A numerical hint, in milliseconds, which indicates the time the calling web app is willing to wait for the creation operation to complete. This hint may be overridden by the browser.
    internal private(set) var timeout: InternalTimeout
    /// The client ID of the OIDC provider
    internal private(set) var clientId: String
    /// The URL to navigate to in order to face the challenge, will be provided if using web flow
    internal private(set) var challengeUrl: String?

    internal init(challengeId: InternalChallengeId, timeout: InternalTimeout, clientId: String, challengeUrl: String? = nil) {
        self.challengeId = challengeId
        self.timeout = timeout
        self.clientId = clientId
        self.challengeUrl = challengeUrl
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case challengeId = "challengeId"
        case timeout = "timeout"
        case clientId = "clientId"
        case challengeUrl = "challengeUrl"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(timeout, forKey: .timeout)
        try container.encode(clientId, forKey: .clientId)
        try container.encodeIfPresent(challengeUrl, forKey: .challengeUrl)
    }
}
