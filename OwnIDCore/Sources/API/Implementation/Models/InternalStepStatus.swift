import Foundation

/// Lifecycle status values recorded for a tracked step.
internal enum InternalStepStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case aborted = "aborted"
    case inProgress = "in-progress"
    case completed = "completed"
    case failed = "failed"
}
