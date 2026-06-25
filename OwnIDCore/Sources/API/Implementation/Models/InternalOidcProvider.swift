import Foundation

internal enum InternalOidcProvider: String, Sendable, Codable, Hashable, CaseIterable {
    case google = "Google"
    case apple = "Apple"
}
