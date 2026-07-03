import Foundation

/// Internal journey-event reporting boundary.
///
/// Reporting success or failure is diagnostic only and must not decide operation or flow results. The caller owns the
/// journey summary and any fallback behavior. Swift task cancellation is returned as ``APIResult/canceled``.
internal protocol EventsAPI: APICapability {
    /// Returns success when reporting is accepted, a typed endpoint failure, an unexpected failure, or cancellation.
    func start(params: EventsAPIParams) async -> APIResult<Void, EventsFailure>
}

/// Caller-owned journey summary and optional trace context for the reporting call.
internal struct EventsAPIParams: Sendable {
    internal let userJourney: UserJourneySummary
    internal let traceParent: String?

    internal init(userJourney: UserJourneySummary, traceParent: String? = nil) {
        self.userJourney = userJourney
        self.traceParent = traceParent
    }
}

internal enum EventsFailure: APIFailure {
    /// Bad request returned by the event-reporting endpoint.
    case badRequest(errorCode: ErrorCode, message: String)
    /// Transport, runtime, unhandled status, or response-shape failure.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    internal var errorCode: ErrorCode {
        switch self {
        case .badRequest(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    internal var message: String {
        switch self {
        case .badRequest(_, let message), .unexpected(_, let message, _): return message
        }
    }

}
