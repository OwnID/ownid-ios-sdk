import Foundation

/// Describes why an operation was canceled or abandoned.
///
/// Reasons are stable categories for cancellation handling and analytics. Some reasons carry optional diagnostic text
/// that is included in ``description`` when present and is not intended for exact string matching.
public enum Reason: CustomStringConvertible, Sendable {
    case timeout
    case userClose(details: String? = nil)
    case moveToOtherChallenge
    case systemError(details: String? = nil)
    case unknown(details: String? = nil)
    case alreadyExists

    public var description: String {
        switch self {
        case .timeout: return "timeout"
        case .userClose(let details):
            guard let details, !details.isEmpty else { return "userClose" }
            return "userClose: \(details)"
        case .moveToOtherChallenge: return "moveToOtherChallenge"
        case .systemError(let details):
            guard let details, !details.isEmpty else { return "systemError" }
            return "systemError: \(details)"
        case .unknown(let details):
            guard let details, !details.isEmpty else { return "unknown" }
            return "unknown: \(details)"
        case .alreadyExists: return "alreadyExists"
        }
    }
}
