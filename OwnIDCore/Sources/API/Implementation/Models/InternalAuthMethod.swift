import Foundation

internal enum InternalAuthMethod: String, Sendable, Codable, Hashable, CaseIterable {
    case otp = "otp"
    case passkey = "passkey"
    case magicLink = "magic-link"
    case password = "password"
    case deferred = "deferred"
    case immediate = "immediate"
    case unknown = "unknown"
    case socialGoogle = "social-google"
    case socialApple = "social-apple"
    case facekey = "facekey"
}
