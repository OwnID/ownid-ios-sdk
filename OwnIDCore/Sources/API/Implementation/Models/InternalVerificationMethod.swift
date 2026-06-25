import Foundation

internal enum InternalVerificationMethod: String, Sendable, Codable, Hashable, CaseIterable {
    case magicLink = "MagicLink"
    case otp = "Otp"
}
