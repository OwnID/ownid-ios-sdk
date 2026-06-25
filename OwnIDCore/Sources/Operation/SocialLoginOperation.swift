import Foundation

/// Authenticates the user with Apple through OwnID OIDC.
///
/// The operation uses the access token from ``SignInWithAppleOperationParams`` or the current OwnID context when
/// available, then starts an Apple OIDC challenge and presents the system Apple Sign-In UI through OwnID Core's default
/// Apple provider.
///
/// On success, the controller completes with ``OperationResult/success(_:)`` containing ``AccessTokenWithUserInfo``.
/// User dismissal or provider cancellation completes with ``OperationResult/canceled(_:)``. Provider, platform UI,
/// access-policy, challenge, and backend errors complete with ``OperationResult/failure(_:)``.
///
/// If the OIDC challenge times out, the operation cancels with ``Reason/timeout``. Calling
/// ``OperationController/abort(reason:)`` while provider UI is active requests best-effort cancellation from both the
/// Apple provider and the OwnID challenge.
///
/// ``availability(params:)`` verifies SDK dependencies and parameter type only; it does not prove that system Apple
/// Sign-In UI presentation will succeed.
///
/// Keep the returned controller strongly referenced while the operation is active. If you need to stop an active
/// operation, call ``OperationController/abort(reason:)``.
public protocol SignInWithAppleOperation: OperationCapability, Sendable
where
    Params == SignInWithAppleOperationParams,
    Result == AccessTokenWithUserInfo,
    Failure == SignInWithAppleOperationFailure
{}

/// Parameters for ``SignInWithAppleOperation``.
///
/// When ``accessToken`` is `nil`, the operation uses the current OwnID context access token when available.
public struct SignInWithAppleOperationParams: CapabilityParams {
    /// An existing access token, if available. Defaults to `nil`.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    /// Creates Apple Sign-In operation parameters.
    ///
    /// - Parameters:
    ///   - accessToken: Existing access token, if available. Defaults to `nil`.
    public init(accessToken: AccessToken? = nil) {
        self.accessToken = accessToken
        self.traceParent = nil
    }

    internal init(accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controller for ``SignInWithAppleOperation`` that resolves to ``AccessTokenWithUserInfo``.
public typealias SignInWithAppleOperationController = any OperationController<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>

/// State value used by the Apple Sign-In operation runtime.
///
/// States progress from ``created`` through ``preparing`` and ``active(apiController:)`` to ``completed(result:)`` with an
/// ``OperationResult`` containing ``AccessTokenWithUserInfo``.
public enum SignInWithAppleOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// Start was requested and prerequisites are being prepared.
    case preparing
    /// The OIDC flow is in progress.
    case active(apiController: any OIDCAPIController)
    /// The operation finished with the given result.
    case completed(result: OperationResult<AccessTokenWithUserInfo, SignInWithAppleOperationFailure>)
}

/// Failure payload returned by ``SignInWithAppleOperation``.
///
/// Every failure is terminal for the current Apple Sign-In operation run. Branch on the category to decide whether to
/// offer another auth path, retry from a new operation, or fix provider/platform integration. Use
/// ``OperationFailure/errorCode`` as a localization key; use `apiFailure`, `underlyingError`, `challengeID`, and
/// `capability` for diagnostics.
public enum SignInWithAppleOperationFailure: OperationFailure, CustomStringConvertible {
    /// Input supplied by the app or generated request is invalid.
    public enum Input: Sendable {
        /// - About: The Apple Sign-In request was rejected before the operation could continue.
        /// - End-user: No direct user action unless the app can collect corrected input.
        /// - Developer action: Inspect access-token context and `apiFailure`.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Access policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The caller is not allowed to start or complete Apple Sign-In in this context.
        /// - End-user: Explain that the requested action is unavailable or offer another auth path.
        /// - Developer action: Check access token claims, app policy, operation requirements, and `apiFailure`.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// OIDC challenge lifecycle failures.
    public enum Challenge: Sendable {
        /// - About: The active OIDC challenge limit was reached.
        /// - End-user: End this attempt and let the user retry later or choose another method.
        /// - Developer action: Do not create another challenge immediately; inspect challenge policy diagnostics.
        case maximumChallengesReached(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The OIDC challenge is invalid, expired, or no longer usable.
        /// - End-user: Ask the user to start a new Apple Sign-In attempt.
        /// - Developer action: Treat the current `challengeID` as terminal and start a new challenge before retrying.
        case invalid(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
        /// - About: The OIDC challenge reached its attempt limit.
        /// - End-user: End this attempt and offer another auth path or a new attempt when appropriate.
        /// - Developer action: Stop the current `challengeID`; start a new operation/controller for a fresh attempt.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, provider, or platform integration failures.
    public enum Integration: Sendable {
        /// - About: Apple Sign-In provider, platform UI, or backend dependency failed.
        /// - End-user: Show a temporary failure state or offer another auth path.
        /// - Developer action: Inspect `apiFailure` and `underlyingError`; verify provider setup and platform availability.
        case providerFailed(
            errorCode: ErrorCode,
            message: String,
            apiFailure: (any APIFailure)? = nil,
            underlyingError: (any Error & Sendable)? = nil
        )
        /// - About: A provider capability required by Apple Sign-In is not configured.
        /// - End-user: No direct user action. Offer another available auth path when possible.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Request input cannot be used.
    case input(Input)
    /// Access policy blocked the operation.
    case access(Access)
    /// OIDC challenge creation or completion failed.
    case challenge(Challenge)
    /// SDK, app, provider, backend, or platform integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic Apple Sign-In failure state and offer another app-level path.
    /// - Developer action: Log operation context, inspect `apiFailure` or `underlyingError`, and do not continue this controller.
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
            case .invalidRequest(let errorCode, let message, _): return (errorCode, message)
            }
        case .access(let access):
            switch access {
            case .forbidden(let errorCode, let message, _): return (errorCode, message)
            }
        case .challenge(let challenge):
            switch challenge {
            case .maximumChallengesReached(let errorCode, let message, _),
                .invalid(let errorCode, let message, _, _),
                .maximumAttemptsReached(let errorCode, let message, _, _):
                return (errorCode, message)
            }
        case .integration(let integration):
            switch integration {
            case .providerFailed(let errorCode, let message, _, _),
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
            case .invalidRequest:
                return "Input.InvalidRequest(errorCode=\(errorCode), message=\(message))"
            }
        case .access(let access):
            switch access {
            case .forbidden:
                return "Access.Forbidden(errorCode=\(errorCode), message=\(message))"
            }
        case .challenge(let challenge):
            switch challenge {
            case .maximumChallengesReached:
                return "Challenge.MaximumChallengesReached(errorCode=\(errorCode), message=\(message))"
            case .invalid:
                return "Challenge.Invalid(errorCode=\(errorCode), message=\(message))"
            case .maximumAttemptsReached:
                return "Challenge.MaximumAttemptsReached(errorCode=\(errorCode), message=\(message))"
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

/// Authenticates the user with Google through OwnID OIDC.
///
/// The operation uses the access token from ``SignInWithGoogleOperationParams`` or the current OwnID context when
/// available, then starts a Google OIDC challenge and delegates Google UI to the registered ``SignInWithGoogle``
/// provider. The app/provider integration owns Google SDK setup, UI presentation details, provider session state, and
/// provider-specific failure mapping.
///
/// On success, the controller completes with ``OperationResult/success(_:)`` containing ``AccessTokenWithUserInfo``.
/// User dismissal or provider cancellation completes with ``OperationResult/canceled(_:)``. Provider, platform UI,
/// access-policy, challenge, and backend errors complete with ``OperationResult/failure(_:)``.
///
/// If the OIDC challenge times out, the operation cancels with ``Reason/timeout``. Calling
/// ``OperationController/abort(reason:)`` while provider UI is active requests best-effort cancellation from both the
/// Google provider and the OwnID challenge.
///
/// ``availability(params:)`` verifies SDK dependencies and parameter type only; it does not prove that provider UI or
/// the Google account picker will succeed. Requires a ``SignInWithGoogle`` capability registered in the active OwnID
/// scope.
///
/// Keep the returned controller strongly referenced while the operation is active. If you need to stop an active
/// operation, call ``OperationController/abort(reason:)``.
public protocol SignInWithGoogleOperation: OperationCapability, Sendable
where
    Params == SignInWithGoogleOperationParams,
    Result == AccessTokenWithUserInfo,
    Failure == SignInWithGoogleOperationFailure
{}

/// Parameters for ``SignInWithGoogleOperation``.
///
/// When ``accessToken`` is `nil`, the operation uses the current OwnID context access token when available.
public struct SignInWithGoogleOperationParams: CapabilityParams {
    /// An existing access token, if available. Defaults to `nil`.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    /// Creates Google Sign-In operation parameters.
    ///
    /// - Parameters:
    ///   - accessToken: Existing access token, if available. Defaults to `nil`.
    public init(accessToken: AccessToken? = nil) {
        self.accessToken = accessToken
        self.traceParent = nil
    }

    internal init(accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controller for ``SignInWithGoogleOperation`` that resolves to ``AccessTokenWithUserInfo``.
public typealias SignInWithGoogleOperationController = any OperationController<AccessTokenWithUserInfo, SignInWithGoogleOperationFailure>

/// State value used by the Google Sign-In operation runtime.
///
/// States progress from ``created`` through ``preparing`` and ``active(apiController:)`` to ``completed(result:)`` with an
/// ``OperationResult`` containing ``AccessTokenWithUserInfo``.
public enum SignInWithGoogleOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// Start was requested and prerequisites are being prepared.
    case preparing
    /// The OIDC flow is in progress.
    case active(apiController: any OIDCAPIController)
    /// The operation finished with the given result.
    case completed(result: OperationResult<AccessTokenWithUserInfo, SignInWithGoogleOperationFailure>)
}

/// Failure payload returned by ``SignInWithGoogleOperation``.
///
/// Every failure is terminal for the current Google Sign-In operation run. Branch on the category to decide whether to
/// offer another auth path, retry from a new operation, or fix provider/platform integration. Use
/// ``OperationFailure/errorCode`` as a localization key; use `apiFailure`, `underlyingError`, `challengeID`, and
/// `capability` for diagnostics.
public enum SignInWithGoogleOperationFailure: OperationFailure, CustomStringConvertible {
    /// Input supplied by the app or generated request is invalid.
    public enum Input: Sendable {
        /// - About: The Google Sign-In request was rejected before the operation could continue.
        /// - End-user: No direct user action unless the app can collect corrected input.
        /// - Developer action: Inspect access-token context and `apiFailure`.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Access policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The caller is not allowed to start or complete Google Sign-In in this context.
        /// - End-user: Explain that the requested action is unavailable or offer another auth path.
        /// - Developer action: Check access token claims, app policy, operation requirements, and `apiFailure`.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// OIDC challenge lifecycle failures.
    public enum Challenge: Sendable {
        /// - About: The active OIDC challenge limit was reached.
        /// - End-user: End this attempt and let the user retry later or choose another method.
        /// - Developer action: Do not create another challenge immediately; inspect challenge policy diagnostics.
        case maximumChallengesReached(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The OIDC challenge is invalid, expired, or no longer usable.
        /// - End-user: Ask the user to start a new Google Sign-In attempt.
        /// - Developer action: Treat the current `challengeID` as terminal and start a new challenge before retrying.
        case invalid(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
        /// - About: The OIDC challenge reached its attempt limit.
        /// - End-user: End this attempt and offer another auth path or a new attempt when appropriate.
        /// - Developer action: Stop the current `challengeID`; start a new operation/controller for a fresh attempt.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, provider, or platform integration failures.
    public enum Integration: Sendable {
        /// - About: Google Sign-In provider, platform UI, or backend dependency failed.
        /// - End-user: Show a temporary failure state or offer another auth path.
        /// - Developer action: Inspect `apiFailure` and `underlyingError`; verify provider setup and platform availability.
        case providerFailed(
            errorCode: ErrorCode,
            message: String,
            apiFailure: (any APIFailure)? = nil,
            underlyingError: (any Error & Sendable)? = nil
        )
        /// - About: A provider capability required by Google Sign-In is not configured.
        /// - End-user: No direct user action. Offer another available auth path when possible.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Request input cannot be used.
    case input(Input)
    /// Access policy blocked the operation.
    case access(Access)
    /// OIDC challenge creation or completion failed.
    case challenge(Challenge)
    /// SDK, app, provider, backend, or platform integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic Google Sign-In failure state and offer another app-level path.
    /// - Developer action: Log operation context, inspect `apiFailure` or `underlyingError`, and do not continue this controller.
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
            case .invalidRequest(let errorCode, let message, _): return (errorCode, message)
            }
        case .access(let access):
            switch access {
            case .forbidden(let errorCode, let message, _): return (errorCode, message)
            }
        case .challenge(let challenge):
            switch challenge {
            case .maximumChallengesReached(let errorCode, let message, _),
                .invalid(let errorCode, let message, _, _),
                .maximumAttemptsReached(let errorCode, let message, _, _):
                return (errorCode, message)
            }
        case .integration(let integration):
            switch integration {
            case .providerFailed(let errorCode, let message, _, _),
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
            case .invalidRequest:
                return "Input.InvalidRequest(errorCode=\(errorCode), message=\(message))"
            }
        case .access(let access):
            switch access {
            case .forbidden:
                return "Access.Forbidden(errorCode=\(errorCode), message=\(message))"
            }
        case .challenge(let challenge):
            switch challenge {
            case .maximumChallengesReached:
                return "Challenge.MaximumChallengesReached(errorCode=\(errorCode), message=\(message))"
            case .invalid:
                return "Challenge.Invalid(errorCode=\(errorCode), message=\(message))"
            case .maximumAttemptsReached:
                return "Challenge.MaximumAttemptsReached(errorCode=\(errorCode), message=\(message))"
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
