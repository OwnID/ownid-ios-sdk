import Foundation

internal enum InternalAuthenticatorAttachment: String, Sendable, Codable, Hashable, CaseIterable {
    case platform = "platform"
    case crossPlatform = "cross-platform"
}
