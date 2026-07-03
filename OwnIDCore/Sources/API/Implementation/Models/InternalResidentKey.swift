import Foundation

internal enum InternalResidentKey: String, Sendable, Codable, Hashable, CaseIterable {
    case required = "required"
    case preferred = "preferred"
    case discouraged = "discouraged"
}
