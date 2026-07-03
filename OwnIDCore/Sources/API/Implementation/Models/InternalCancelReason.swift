import Foundation

internal enum InternalCancelReason: String, Sendable, Codable, Hashable, CaseIterable {
    case timeout = "timeout"
    case userClose = "userClose"
    case moveToOtherChallenge = "moveToOtherChallenge"
    case systemError = "systemError"
    case unknown = "unknown"
    case alreadyExists = "alreadyExists"
}
