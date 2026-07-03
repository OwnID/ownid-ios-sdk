import Foundation

internal enum InternalScopeType: String, Sendable, Codable, Hashable, CaseIterable {
    case data = "data"
    case channel = "channel"
    case session = "session"
}
