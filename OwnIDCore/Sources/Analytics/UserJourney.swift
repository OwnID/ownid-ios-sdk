import Foundation

/// Collects best-effort analytics for one SDK user journey.
///
/// SDK flows use this internal contract to record flow metadata, operation starts, clicks, operation completions,
/// login ID hints, referer data, and a terminal outcome. Completion schedules a journey summary submission.
/// Analytics failures are diagnostic only and must not decide SDK flow or operation results.
internal protocol UserJourney: Capability, Sendable {
    /// Starts tracking a flow or updates the active flow metadata.
    ///
    /// If a flow is already active, the collector updates its source and non-nil name instead of settling it.
    /// Use `switchToFlow(flowID:name:source:)` when one flow should be marked as switched before another flow starts.
    ///
    /// - Parameters:
    ///   - name: Optional flow name used in analytics.
    ///   - source: Origin that started or resumed the flow.
    ///   - traceParent: Optional trace context seed forwarded with the analytics summary. Nil leaves any retained seed unchanged.
    func startFlow(name: String?, source: FlowInfo.Source, traceParent: String?) async

    /// Marks the active flow as switched and starts tracking the target flow.
    ///
    /// In-progress operation steps in the previous flow are recorded as aborted. `flowID` is used as the target flow
    /// identifier when present; otherwise the implementation creates one.
    ///
    /// - Parameters:
    ///   - flowID: Optional identifier for the target flow. When nil, the implementation creates one.
    ///   - name: Optional target flow name used in analytics.
    ///   - source: Origin that switched to the target flow.
    func switchToFlow(flowID: String?, name: String?, source: FlowInfo.Source) async

    /// Adds a login ID hint to the journey.
    ///
    /// Implementations may enrich the entry with returning-user metadata when the local user repository contains the
    /// same login ID. The hint is privacy-sensitive analytics data and must not be treated as authenticated user state.
    ///
    /// - Parameter loginID: Login ID hint to include in the journey summary.
    func setUserInfo(_ loginID: LoginID) async

    /// Replaces the referer URL or screen identifier reported for the journey.
    ///
    /// - Parameter referer: Referer URL or screen identifier to report.
    func setReferer(_ referer: String) async

    /// Records that an operation step started in the active flow.
    ///
    /// - Parameter operationID: Operation step identifier to add to the active flow.
    func startOperation(operationID: OperationID) async

    /// Increments the click counter for an operation step when that step is known to the active flow.
    ///
    /// - Parameter operationID: Operation step identifier whose click count should be incremented.
    func addOperationClick(operationID: OperationID) async

    /// Records operation step completion and optional diagnostic metadata.
    ///
    /// A nil `errorCode` records success, `ErrorCode.aborted` records an aborted step, and other errors record a failed
    /// step with the supplied source and message.
    ///
    /// - Parameters:
    ///   - operationID: Operation step identifier to complete.
    ///   - errorCode: Optional error classification. Nil records success.
    ///   - source: Optional diagnostic source for failed steps.
    ///   - message: Optional diagnostic message for failed steps.
    func completeOperation(operationID: OperationID, errorCode: ErrorCode?, source: String?, message: String?) async

    /// Settles the active flow and schedules journey summary submission.
    ///
    /// - Parameter outcome: Terminal analytics outcome for the active flow.
    func completeFlow(_ outcome: UserJourneyOutcome)
}

/// Terminal analytics outcome for a flow.
internal enum UserJourneyOutcome: Sendable {
    /// Flow completed with a login.
    case loggedIn(AuthMethod)
    /// Flow completed with registration.
    case registered(AuthMethod?)
    /// Flow completed without a narrower login or registration classification.
    case completed(AuthMethod?)
    /// Flow completed with a diagnostic error classification.
    case error(errorCode: ErrorCode, source: String?, message: String?)
}

internal struct UserJourneySummary: Sendable, Hashable {
    internal struct Reporter: Sendable, Hashable {
        internal enum Service: String, Sendable {
            case webSdk = "web-sdk"
            case androidSdk = "android-sdk"
            case iosSdk = "ios-sdk"
        }
        internal let service: Service
        internal let origin: String
        internal let referer: String
        internal let version: String?
    }

    internal struct EventInfo: Sendable, Hashable {
        internal enum `Type`: String, Sendable { case journeySummary = "journey-summary" }
        internal let type: `Type`
        internal let flows: [FlowInfo]
    }

    internal struct ClientDeviceInfo: Sendable, Hashable {
        internal let isPlatformAuthenticatorAvailable: Bool
        internal let isWebView: Bool
        internal let isMobileNative: Bool
    }

    internal struct UserInfo: Sendable, Hashable {
        internal let loginId: LoginID
        internal let returningUser: Bool?
        internal let lastAuthMethod: AuthMethod?
    }

    internal let id: String
    internal let reporter: Reporter
    internal let eventInfo: EventInfo
    internal let deviceInfo: ClientDeviceInfo
    internal let userInfo: [UserInfo]
}

internal struct ClientError: Sendable, Hashable {
    internal let errorCode: String
    internal let source: String?
    internal let message: String?
}

/// Analytics record for a single flow inside a user journey.
///
/// This SPI model carries flow identity, source, status, timestamps, switched-flow linkage, errors, steps, and insights
/// across SDK analytics boundaries. It is not an app-developer integration surface.
@_spi(OwnIDInternal)
public struct FlowInfo: Sendable, Hashable {
    /// Origin that started or switched to the flow.
    public enum Source: String, Sendable {
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

    internal enum Status: String, Sendable {
        case aborted = "aborted"
        case inProgress = "in-progress"
        case completed = "completed"
        case switched = "switched"
        case failed = "failed"
    }

    internal struct Insights: Sendable, Hashable {
        internal let duration: Int64?
        internal let errorRate: Double?
        internal let retries: Int?
        internal let clicksCount: Int?
        internal let authMethod: AuthMethod?
        internal let loggedIn: Bool?
        internal let registered: Bool?
    }

    internal let id: String
    internal let name: String?
    internal let source: Source
    internal let status: Status
    internal let startedAt: Date
    internal let completedAt: Date?
    internal let errors: [ClientError]?
    internal let switchedToFlow: String?
    internal let insights: Insights?
    internal let steps: [Step]
}

internal struct Step: Sendable, Hashable {
    internal enum Status: String, Sendable {
        case aborted = "aborted"
        case inProgress = "in-progress"
        case completed = "completed"
        case failed = "failed"
    }

    internal struct Insights: Sendable, Hashable {
        internal let duration: Int64?
        internal let retries: Int?
        internal let clicksCount: Int?  // omit if 0 at construction
    }

    internal let operationType: OperationType
    internal let name: String?
    internal let status: Status
    internal let startedAt: Date
    internal let completedAt: Date?
    internal let errors: [ClientError]?
    internal let insights: Insights?
}
