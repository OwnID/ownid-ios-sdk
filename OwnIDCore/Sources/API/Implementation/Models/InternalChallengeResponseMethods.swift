import Foundation

/// Verification methods available for a started challenge.
///
/// At least one of ``otp`` or ``magicLink`` must be present.
internal struct InternalChallengeResponseMethods: Sendable, Codable, Hashable {
    /// OTP verification configuration.
    internal private(set) var otp: InternalChallengeResponseMethodsOtp?
    /// Magic-link verification availability marker.
    internal private(set) var magicLink: InternalChallengeResponseMethodsMagicLink?

    internal init(otp: InternalChallengeResponseMethodsOtp? = nil, magicLink: InternalChallengeResponseMethodsMagicLink? = nil) {
        self.otp = otp
        self.magicLink = magicLink
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case otp = "otp"
        case magicLink = "magicLink"
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.otp = try container.decodeIfPresent(InternalChallengeResponseMethodsOtp.self, forKey: .otp)
        self.magicLink = try container.decodeIfPresent(InternalChallengeResponseMethodsMagicLink.self, forKey: .magicLink)
        guard otp != nil || magicLink != nil else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "At least one of otp or magicLink must be present.")
            )
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard otp != nil || magicLink != nil else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: container.codingPath, debugDescription: "At least one of otp or magicLink must be present.")
            )
        }
        try container.encodeIfPresent(otp, forKey: .otp)
        try container.encodeIfPresent(magicLink, forKey: .magicLink)
    }
}
