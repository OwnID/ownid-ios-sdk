import Foundation

internal struct InternalStartOidcChallengeRequest: Sendable, Codable, Hashable {
    /// A login ID hint for the OIDC provider
    internal private(set) var loginIdHint: String?
    /// The response type that will be used to resolve the challenge. Currently only a subset of the types in the protocol are supported
    internal private(set) var oauthResponseType: InternalStartOidcChallengeRequestOauthResponseType
    /// The redirect URI to be used in an OIDC web flow, defaults to the preconfigured app's redirect uri
    internal private(set) var redirectUri: String?

    internal init(
        loginIdHint: String? = nil,
        oauthResponseType: InternalStartOidcChallengeRequestOauthResponseType,
        redirectUri: String? = nil
    ) {
        self.loginIdHint = loginIdHint
        self.oauthResponseType = oauthResponseType
        self.redirectUri = redirectUri
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case loginIdHint = "loginIdHint"
        case oauthResponseType = "oauthResponseType"
        case redirectUri = "redirectUri"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(loginIdHint, forKey: .loginIdHint)
        try container.encode(oauthResponseType, forKey: .oauthResponseType)
        try container.encodeIfPresent(redirectUri, forKey: .redirectUri)
    }
}
