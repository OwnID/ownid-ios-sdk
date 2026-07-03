import Foundation

/// Lifecycle status values recorded for a tracked flow.
internal enum InternalFlowStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case aborted = "aborted"
    case inProgress = "in-progress"
    case completed = "completed"
    case switched = "switched"
    case failed = "failed"
}
