import Foundation

/// Authenticates a user and returns a ``LoginResponse``.
///
/// Routing is token-first:
/// - If an access token is resolved from params or context, runs token-only login and ignores login ID.
/// - Else if a login ID is resolved from params or context, runs discover mode (no token).
/// - Else returns ``OperationResult/failure(_:)``.
///
/// ``availability(params:)`` mirrors that input precedence as a preflight check: it is available when a token is
/// present, or when a resolvable login ID validates successfully. The operation rechecks inputs after ``start(params:)``,
/// so callers should still handle terminal failure or cancellation.
///
/// On API success, the operation returns ``LoginResponse`` as-is from either route:
/// ``LoginResponse/success(_:)``, ``LoginResponse/authRequired(_:)``, ``LoginResponse/accountNotFound(_:)``, or
/// ``LoginResponse/accountBlocked(_:)``. Validation, access-policy, integration, and backend errors complete with
/// ``OperationResult/failure(_:)``. Caller or SDK cancellation completes with ``OperationResult/canceled(_:)``.
///
/// Keep the returned controller strongly referenced while the operation is active. If you need to stop an active
/// operation, call ``OperationController/abort(reason:)``.
public protocol LoginOperation: OperationCapability, Sendable
where
    Params == LoginOperationParams,
    Result == LoginResponse,
    Failure == LoginOperationFailure
{}

/// Parameters for ``LoginOperation``.
///
/// ``loginID`` and ``accessToken`` default to `nil`; when absent, the operation resolves values from the current OwnID context.
public struct LoginOperationParams: CapabilityParams, Sendable {
    /// Login identifier used for discover when no access token is available. Defaults to `nil`.
    public let loginID: LoginID?
    /// Access token used for token-first login. Defaults to `nil`.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    /// Creates login operation parameters.
    ///
    /// - Parameters:
    ///   - loginID: Login identifier used for discover when no access token is available. Defaults to `nil`.
    ///   - accessToken: Access token used for token-first login. Defaults to `nil`.
    public init(loginID: LoginID? = nil, accessToken: AccessToken? = nil) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.traceParent = nil
    }

    internal init(accessToken: AccessToken? = nil, loginID: LoginID? = nil, traceParent: String? = nil) {
        self.accessToken = accessToken
        self.loginID = loginID
        self.traceParent = traceParent
    }
}

/// Controller for ``LoginOperation`` that resolves to ``LoginResponse``.
public typealias LoginOperationController = any OperationController<LoginResponse, LoginOperationFailure>

/// State value used by the login operation runtime.
///
/// States progress from ``created`` to ``preparing`` and then ``completed(_:)`` with an ``OperationResult``
/// containing a ``LoginResponse``.
public enum LoginOperationState: OperationState, Sendable {
    /// Operation has been instantiated but not yet started.
    case created
    /// Start was requested and prerequisites are being prepared.
    case preparing
    /// Operation finished with the given result.
    case completed(OperationResult<LoginResponse, LoginOperationFailure>)
}

/// Failure payload returned by ``LoginOperation``.
///
/// Every failure is terminal for the current operation run. Branch on the concrete case and category to decide whether
/// to collect corrected input, offer another login path, fix integration, or show a final error.
///
/// Use ``OperationFailure/errorCode`` as a localization key. Use associated values such as `apiFailure`,
/// `underlyingError`, `capability`, `loginID`, and `regex` for diagnostics and app routing.
public enum LoginOperationFailure: OperationFailure, CustomStringConvertible {
    /// Missing, invalid, or unsupported login input.
    public enum Input: Sendable {
        /// - About: The operation could not resolve either an access token or a login ID to start login.
        /// - End-user: Ask the user to provide an identifier or sign in through another available path.
        /// - Developer action: Pass ``LoginOperationParams/loginID`` or ``LoginOperationParams/accessToken``, or provide
        ///   one through OwnID context.
        case missingLoginIDOrAccessToken(errorCode: ErrorCode, message: String)
        /// - About: The resolved login ID value failed validation.
        /// - End-user: Ask the user to correct the identifier.
        /// - Developer action: Keep client-side validation aligned with OwnID configuration. Use `regex` and
        ///   `apiFailure` only for diagnostics.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The resolved login ID type is not supported for login discovery.
        /// - End-user: Ask the user for a supported identifier type when the app lets the user choose one.
        /// - Developer action: Compare the supplied login ID type with the app's OwnID login ID configuration. Inspect
        ///   `apiFailure` when present.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: Login input was rejected before the operation could be routed to a successful outcome.
        /// - End-user: No direct user action unless the app can collect corrected input.
        /// - Developer action: Inspect the supplied token/login-ID context and `apiFailure` to determine which input invariant failed.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Access policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The caller is authenticated but not allowed to perform this login operation.
        /// - End-user: Explain that the requested action is unavailable.
        /// - Developer action: Check access token claims, app policy, operation requirements, and `apiFailure`.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, provider, or backend integration failures.
    public enum Integration: Sendable {
        /// - About: A configured backend/provider dependency failed while processing login.
        /// - End-user: Show a temporary failure state or offer another available path.
        /// - Developer action: Log provider context, inspect `apiFailure`, and avoid aggressive automatic retries.
        case providerFailed(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: A provider capability required by login is not configured.
        /// - End-user: No direct user action. Offer another available path when possible.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Login input cannot be used.
    case input(Input)
    /// Access policy blocked the operation.
    case access(Access)
    /// SDK, app, backend, or provider integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic failure state. Retrying may be reasonable if the app can safely restart login.
    /// - Developer action: Log operation context, inspect `apiFailure` or `underlyingError`, and avoid automatic retry loops.
    case unexpected(
        errorCode: ErrorCode = .unknown,
        message: String,
        apiFailure: (any APIFailure)? = nil,
        underlyingError: (any Error & Sendable)? = nil
    )

    private var payload: (ErrorCode, String) {
        switch self {
        case .input(let input):
            switch input {
            case .missingLoginIDOrAccessToken(let errorCode, let message),
                .invalidLoginID(let errorCode, let message, _, _, _),
                .unsupportedLoginIDType(let errorCode, let message, _),
                .invalidRequest(let errorCode, let message, _):
                return (errorCode, message)
            }
        case .access(let access):
            switch access {
            case .forbidden(let errorCode, let message, _): return (errorCode, message)
            }
        case .integration(let integration):
            switch integration {
            case .providerFailed(let errorCode, let message, _),
                .missingProvider(let errorCode, let message, _, _):
                return (errorCode, message)
            }
        case .unexpected(let errorCode, let message, _, _): return (errorCode, message)
        }
    }

    public var errorCode: ErrorCode { payload.0 }
    public var message: String { payload.1 }
    public var description: String {
        switch self {
        case .input(let input):
            switch input {
            case .missingLoginIDOrAccessToken:
                return "Input.MissingLoginIDOrAccessToken(errorCode=\(errorCode), message=\(message))"
            case .invalidLoginID:
                return "Input.InvalidLoginID(errorCode=\(errorCode), message=\(message))"
            case .unsupportedLoginIDType:
                return "Input.UnsupportedLoginIDType(errorCode=\(errorCode), message=\(message))"
            case .invalidRequest:
                return "Input.InvalidRequest(errorCode=\(errorCode), message=\(message))"
            }
        case .access(let access):
            switch access {
            case .forbidden:
                return "Access.Forbidden(errorCode=\(errorCode), message=\(message))"
            }
        case .integration(let integration):
            switch integration {
            case .providerFailed:
                return "Integration.ProviderFailed(errorCode=\(errorCode), message=\(message))"
            case .missingProvider:
                return "Integration.MissingProvider(errorCode=\(errorCode), message=\(message))"
            }
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
