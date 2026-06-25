import Foundation

internal struct InternalStartVerificationRequest: Sendable, Codable, Hashable {
    internal private(set) var loginId: InternalLoginId?
    /// An optional hint identifier for the login ID
    internal private(set) var loginIDHintID: String?
    internal private(set) var verificationMethods: [InternalVerificationMethod]?
    /// An optional URL to which the user will be redirected to after clicking a magic link, if this
    /// method is used in the verification
    internal private(set) var magicLinkRedirectURL: String?

    internal init(
        loginId: InternalLoginId? = nil,
        loginIDHintID: String? = nil,
        verificationMethods: [InternalVerificationMethod]? = nil,
        magicLinkRedirectURL: String? = nil
    ) {
        self.loginId = loginId
        self.loginIDHintID = loginIDHintID
        self.verificationMethods = verificationMethods
        self.magicLinkRedirectURL = magicLinkRedirectURL
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case loginId = "loginId"
        case loginIDHintID = "loginIdHintId"
        case verificationMethods = "verificationMethods"
        case magicLinkRedirectURL = "magicLinkRedirectUrl"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(loginId, forKey: .loginId)
        try container.encodeIfPresent(loginIDHintID, forKey: .loginIDHintID)
        try container.encodeIfPresent(verificationMethods, forKey: .verificationMethods)
        try container.encodeIfPresent(magicLinkRedirectURL, forKey: .magicLinkRedirectURL)
    }
}
