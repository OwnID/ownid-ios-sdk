import Foundation

/// OTP verification configuration for a challenge.
internal struct InternalChallengeResponseMethodsOtp: Sendable, Codable, Hashable {
    /// Expected OTP code length.
    internal private(set) var length: Int?

    internal init(length: Int? = nil) {
        self.length = length
    }

    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case length = "length"
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(length, forKey: .length)
    }
}
