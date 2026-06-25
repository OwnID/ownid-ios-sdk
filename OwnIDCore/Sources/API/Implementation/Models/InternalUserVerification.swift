import Foundation

internal enum InternalUserVerification: String, Sendable, Codable, Hashable, CaseIterable {
    case preferred = "preferred"
    case required = "required"
    case discouraged = "discouraged"
}
