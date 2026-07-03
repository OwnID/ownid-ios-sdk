import Foundation

/// Internal app-configuration fetch boundary.
///
/// This contract performs one network fetch and maps the endpoint response. ``AppConfigProvider`` owns fallback,
/// storage, retry, and stream emission semantics. Swift task cancellation is returned as ``APIResult/canceled``.
internal protocol AppConfigAPI: APICapability {
    /// Returns the mapped configuration, a typed endpoint failure, an unexpected failure, or cancellation.
    func start(params: AppConfigAPIParams?) async -> APIResult<AppConfig, AppConfigFailure>
}

/// Optional trace context for correlating the fetch with the caller's work.
internal struct AppConfigAPIParams: Sendable {
    internal let traceParent: String?

    internal init(traceParent: String? = nil) {
        self.traceParent = traceParent
    }
}

internal enum AppConfigFailure: APIFailure {
    /// Bad request returned by the app-configuration endpoint.
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
