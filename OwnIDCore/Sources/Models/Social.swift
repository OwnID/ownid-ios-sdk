import Foundation

/// Supported social identity providers.
///
/// `rawValue` is the stable OwnID provider string used in SDK API requests and responses. Encoding writes the canonical
/// raw value (`"Apple"` or `"Google"`). Decoding accepts those values case-insensitively and fails for unknown
/// providers; `SocialProviderID(rawValue:)` remains case-sensitive.
public enum SocialProviderID: String, Codable, Sendable {
    case apple = "Apple"

    case google = "Google"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawProvider = try container.decode(String.self)
        switch rawProvider.lowercased() {
        case "apple": self = .apple
        case "google": self = .google
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid social provider: \(rawProvider)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Server-issued challenge for a social sign-in attempt.
///
/// `Codable` uses the public `challengeId`, `timeout`, `clientId`, and `challengeUrl` keys. The SDK keeps
/// ``clientID`` and ``challengeURL`` as supplied; ``timeout`` is normalized by ``Timeout``.
public struct SocialChallenge: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case timeout
        case clientID = "clientId"
        case challengeURL = "challengeUrl"
    }

    public let challengeID: ChallengeID
    public let timeout: Timeout
    public let clientID: String
    public let challengeURL: String?

    /// Creates a social sign-in challenge.
    ///
    /// - Parameters:
    ///   - challengeID: Unique challenge identifier.
    ///   - timeout: Timeout for the challenge.
    ///   - clientID: OAuth client ID for the social provider.
    ///   - challengeURL: URL to navigate to in order to complete the challenge, when provided.
    public init(challengeID: ChallengeID, timeout: Timeout, clientID: String, challengeURL: String?) {
        self.challengeID = challengeID
        self.timeout = timeout
        self.clientID = clientID
        self.challengeURL = challengeURL
    }

    public var description: String {
        "SocialChallenge(challengeId: \(challengeID), timeout: \(timeout), clientId: \(clientID), challengeUrl: \(String(describing: challengeURL)))"
    }
}

/// OAuth response type requested during a social sign-in attempt.
///
/// When this value is passed to SDK OIDC APIs, ``code`` maps to the OwnID `code` request value and ``idToken`` maps to
/// `id_token`. The `Codable` conformance uses Swift's synthesized enum representation, not those backend wire strings.
public enum OAuthResponseType: Codable, Sendable {
    case code

    case idToken
}

/// An access token bundled with the user's login ID, profile info, and the social ``provider``.
///
/// The SDK returns this model after a successful social sign-in attempt. The app owns the resulting token and profile
/// data and decides how to exchange or persist them at its authentication boundary. `description` redacts ``userInfo``
/// and relies on ``AccessToken`` to redact the token value. `Codable` uses the public `accessToken`, `loginId`,
/// `userInfo`, and `provider` keys.
public struct AccessTokenWithUserInfo: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey {
        case accessToken
        case loginID = "loginId"
        case userInfo
        case provider
    }

    public let accessToken: AccessToken
    public let loginID: LoginID
    public let userInfo: [String: String]
    public let provider: SocialProviderID

    /// Creates a social sign-in token result.
    ///
    /// - Parameters:
    ///   - accessToken: Signed authentication token issued after successful social sign-in.
    ///   - loginID: Login identifier associated with the authenticated user.
    ///   - userInfo: User information returned by the social provider as string key-value pairs.
    ///   - provider: Social provider that issued the authenticated result.
    public init(
        accessToken: AccessToken,
        loginID: LoginID,
        userInfo: [String: String] = [:],
        provider: SocialProviderID
    ) {
        self.accessToken = accessToken
        self.loginID = loginID
        self.userInfo = userInfo
        self.provider = provider
    }

    public var description: String {
        "AccessTokenWithUserInfo(accessToken: \(accessToken), loginID: \(loginID), userInfo: '*', provider: \(provider.rawValue))"
    }
}
