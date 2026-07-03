import Foundation

internal struct InternalAttestationOptionsResponseAuthenticatorSelection: Sendable, Codable, Hashable {
    internal private(set) var authenticatorAttachment: InternalAuthenticatorAttachment?
    internal private(set) var userVerification: InternalUserVerification?
    internal private(set) var residentKey: InternalResidentKey?

    internal init(
        authenticatorAttachment: InternalAuthenticatorAttachment? = nil,
        userVerification: InternalUserVerification? = nil,
        residentKey: InternalResidentKey? = nil
    ) {
        self.authenticatorAttachment = authenticatorAttachment
        self.userVerification = userVerification
        self.residentKey = residentKey
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case authenticatorAttachment = "authenticatorAttachment"
        case userVerification = "userVerification"
        case residentKey = "residentKey"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(authenticatorAttachment, forKey: .authenticatorAttachment)
        try container.encodeIfPresent(userVerification, forKey: .userVerification)
        try container.encodeIfPresent(residentKey, forKey: .residentKey)
    }
}
