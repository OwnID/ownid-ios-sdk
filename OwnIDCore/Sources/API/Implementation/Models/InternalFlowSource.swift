import Foundation

/// Source that initiated a tracked flow.
internal enum InternalFlowSource: String, Sendable, Codable, Hashable, CaseIterable {
    case widgetButton = "widget-button"
    case returningUserPrompt = "returning-user-prompt"
    case recoveryPrompt = "recovery-prompt"
    case enrollPrompt = "enroll-prompt"
    case elite = "elite"
    case agentAuthorizing = "agent-authorizing"
    case deferred = "deferred"
    case explicit = "explicit"
    case implicit = "implicit"
}
