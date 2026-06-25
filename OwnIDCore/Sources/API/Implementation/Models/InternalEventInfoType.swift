import Foundation

/// Event categories accepted by the analytics endpoint.
internal enum InternalEventInfoType: String, Sendable, Codable, Hashable, CaseIterable {
    case journeySummary = "journey-summary"
}
