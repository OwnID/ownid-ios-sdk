import Foundation

/// OwnID-driven authentication flow for Boost login and create-passkey journeys.
///
/// Boost is a high-level flow layer. It chooses among SDK operations, provider callbacks, current ``Context``, and
/// stored user state, then settles once with ``FlowResult``. Apps that need to control individual challenge APIs or
/// platform passkey UI directly should use the operation or direct API layer instead.
///
/// Call `start(_:)` with an optional ``BoostFlowContext`` to begin the flow. Boost is token-first when the flow context
/// or current ``Context`` contains an access token: the SDK derives the login ID from that token and starts the token
/// login path for that run. Without an access token, login ID is resolved from ``BoostFlowContext``, the current
/// ``Context``, then the stored last user before login-ID collection is shown. Setting
/// ``BoostFlowContext/ignoreLastUser`` to `true` only disables the stored last-user fallback; it does not ignore
/// explicit flow-context or current-context login IDs.
///
/// Use ``BoostLoginFlow`` for sign-in screens and ``BoostCreatePasskeyFlow`` when account creation should include the
/// OwnID create-passkey path. Both variants are asynchronous, may present operation UI, may call configured app
/// providers, and settle through ``FlowResult/success(_:)``, ``FlowResult/canceled(_:)``, or
/// ``FlowResult/failure(_:)``.
///
/// The caller owns the returned controller. Keep it strongly referenced while the flow is active.
///
/// Use the returned flow controller's `abort(reason:)` method for semantic cancellation when you have an explicit
/// reason that should be propagated to the terminal result. If the owner is torn down while the flow is still active,
/// abort the flow with an appropriate ``Reason``. Boost controllers do not expose a separate cleanup method; abort
/// explicitly when an owner lifecycle ends while the flow is active.
public protocol BoostFlow: FlowCapability, Sendable {
    associatedtype ResponseType: Sendable
    associatedtype Failure: FlowFailure
}

/// Controls a running Boost login flow.
///
/// - Call ``whenSettled()`` to await the cached final ``FlowResult``.
/// - Use ``abort(reason:)`` for semantic cancellation with an explicit ``Reason``.
///
/// The caller owns this controller. Keep it strongly referenced while the flow is active, and abort it if the owner
/// is torn down before settlement.
///
/// Cancellation is best-effort and is forwarded to the active child operation or flow when one is running. Calling
/// ``abort(reason:)`` after settlement is safe and has no effect.
public protocol BoostLoginFlowController: Sendable {
    /// Requests flow cancellation with an explicit `reason`.
    ///
    /// Use this API when cancellation semantics are meaningful to the caller and should be reflected in the terminal result.
    ///
    /// If the flow is already settled, this call has no effect.
    func abort(reason: Reason)

    /// Awaits the flow's completion and returns the cached ``FlowResult``.
    func whenSettled() async -> FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>

}

/// Controls a running Boost create-passkey flow.
///
/// - Call ``whenSettled()`` to await the cached final ``FlowResult``.
/// - Use ``abort(reason:)`` for semantic cancellation with an explicit ``Reason``.
///
/// The caller owns this controller. Keep it strongly referenced while the flow is active, and abort it if the owner
/// is torn down before settlement.
///
/// Cancellation is best-effort and is forwarded to the active child operation or flow when one is running. Calling
/// ``abort(reason:)`` after settlement is safe and has no effect.
public protocol BoostCreatePasskeyFlowController: Sendable {
    /// Requests flow cancellation with an explicit `reason`.
    ///
    /// Use this API when cancellation semantics are meaningful to the caller and should be reflected in the terminal result.
    ///
    /// If the flow is already settled, this call has no effect.
    func abort(reason: Reason)

    /// Awaits the flow's completion and returns the cached ``FlowResult``.
    func whenSettled() async -> FlowResult<BoostFlowResponse, BoostCreatePasskeyFlowFailure>

}

extension FlowController: BoostLoginFlowController where Success == BoostFlowLoginResponse, Failure == BoostLoginFlowFailure {}

extension FlowController: BoostCreatePasskeyFlowController where Success == BoostFlowResponse, Failure == BoostCreatePasskeyFlowFailure {}

/// Successful login response from a Boost flow.
///
/// - ``loginID``: The authenticated user's login identifier.
/// - ``authMethod``: The authentication method used, such as passkey or OTP.
/// - ``accessToken``: The OwnID-issued access token.
/// - ``sessionPayload``: Server-provided payload for app session integration. The same value is passed to
///   ``SessionCreate`` when that provider is configured and available. Structured values remain JSON text. If OwnID
///   returns a plain string, this property contains that string value.
/// - ``session``: App-defined value returned by ``SessionCreate`` in this response. When no provider is configured or
///   the provider is unavailable for these params, the flow still succeeds and this value is `nil`. The SDK does not
///   interpret, serialize, or persist the value. A provider failure is terminal and is reported as a session-creation
///   flow failure instead of a successful login response.
public struct BoostFlowLoginResponse: Sendable, CustomStringConvertible {
    /// The authenticated user's login identifier.
    public let loginID: LoginID
    /// The authentication method used (e.g. passkey, OTP).
    public let authMethod: AuthMethod
    /// The OwnID-issued access token.
    public let accessToken: AccessToken
    /// Server-provided payload for app session integration.
    ///
    /// The same value is passed to ``SessionCreate`` when that provider is configured and available. Structured values
    /// remain JSON text. If OwnID returns a plain string, this property contains that string value.
    public let sessionPayload: String
    /// App-defined value returned by ``SessionCreate`` in this response.
    ///
    /// The SDK does not interpret, serialize, or persist the value.
    public let session: (any Sendable)?

    public init(
        loginID: LoginID,
        authMethod: AuthMethod,
        accessToken: AccessToken,
        sessionPayload: String,
        session: (any Sendable)? = nil
    ) {
        self.loginID = loginID
        self.authMethod = authMethod
        self.accessToken = accessToken
        self.sessionPayload = sessionPayload
        self.session = session
    }

    /// A redacted debug string that hides sensitive session values.
    public var description: String {
        let maskedSession = session != nil ? "'*'" : "nil"
        return
            "Login(loginID: \(loginID), authMethod: \(authMethod), accessToken: \(String(describing: accessToken)), sessionPayload='*', session=\(maskedSession))"
    }
}

/// Successful create-passkey response from a Boost flow.
///
/// - ``loginID``: The registered user's login identifier.
/// - ``proofToken``: Token proving the create-passkey operations succeeded, or `nil` when no proof is available. A
///   proof token is not a host app session token.
/// - ``ownIdData``: Value the app can forward to your vendor backend, or `nil` when no proof is available. Structured
///   values remain JSON text. If OwnID returns a plain string, this property contains that string value. The SDK does
///   not interpret or persist this value.
public struct BoostFlowCreatePasskeyResponse: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The registered user's login identifier.
    public let loginID: LoginID
    /// Token proving the create-passkey operations succeeded, or `nil` when no proof is available.
    public let proofToken: ProofToken?
    /// Value the app can forward to your vendor backend, or `nil` when no proof is available.
    /// Structured values remain JSON text. If OwnID returns a plain string, this property contains that string value.
    public let ownIdData: String?

    public init(loginID: LoginID, proofToken: ProofToken? = nil, ownIdData: String? = nil) {
        self.loginID = loginID
        self.proofToken = proofToken
        self.ownIdData = ownIdData
    }

    /// A redacted debug string that hides `ownIdData` when present.
    public var description: String {
        let maskedOwnIdData = ownIdData != nil ? "'*'" : "nil"
        return "CreatePasskey(loginID: \(loginID), proofToken: \(String(describing: proofToken)), ownIdData=\(maskedOwnIdData))"
    }
}

/// Terminal response from a Boost create-passkey flow (either a login or create-passkey outcome).
public enum BoostFlowResponse: Sendable {
    /// The user was recognized and logged in.
    case login(BoostFlowLoginResponse)
    /// The create-passkey path completed.
    case createPasskey(BoostFlowCreatePasskeyResponse)
}

/// Boost flow specialized for login; resolves to ``BoostFlowLoginResponse``.
///
/// The flow is token-first:
/// - If an access token is available in this flow context or the current ``Context``, login ID is derived from the
///   token and login runs token-only.
/// - If token-based login ID resolution fails, the flow completes with ``FlowResult/failure(_:)``.
/// - If no access token is available, the flow uses any login-ID hint from ``BoostFlowContext``, the current
///   ``Context``, or the stored last user when ``BoostFlowContext/ignoreLastUser`` is not `true` before showing
///   login-ID collection.
///
/// When OwnID requires additional authentication, the flow uses available operations to satisfy the requirements. User
/// or owner cancellation settles as ``FlowResult/canceled(_:)``. Missing dependencies, unavailable operations, provider
/// failures, account outcomes, and unmet requirements settle as ``FlowResult/failure(_:)``.
///
/// On successful login, the flow updates the stored last user when that capability is configured.
public protocol BoostLoginFlow: BoostFlow where ResponseType == BoostFlowLoginResponse, Failure == BoostLoginFlowFailure {
    /// Starts the Boost login flow with the given context.
    ///
    /// - Parameter context: Configuration for the flow.
    /// - Returns: A controller to await the result or cancel the flow.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is
    /// still active. Repeated calls on the same flow instance return the same controller and do not start a second run.
    func start(_ context: BoostFlowContext) -> any BoostLoginFlowController
}

extension BoostLoginFlow {
    /// Starts the Boost login flow with a default empty context.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is
    /// still active.
    public func start() -> any BoostLoginFlowController {
        start(.empty)
    }
}

/// Boost flow specialized for create-passkey; resolves to ``BoostFlowResponse`` (login or create-passkey).
///
/// The flow is token-first:
/// - If an access token is available in this flow context or the current ``Context``, login ID is derived from the
///   token and login runs token-only.
/// - If token-based login ID resolution fails, the flow completes with ``FlowResult/failure(_:)``.
/// - If no access token is available, the flow resolves or collects login ID and proceeds with login.
///   ``BoostFlowContext/ignoreLastUser`` only disables the stored last-user fallback; explicit flow-context and
///   current-context login IDs remain eligible.
///
/// If login succeeds, the result is ``BoostFlowResponse/login(_:)`` and uses the same ``SessionCreate`` boundary as
/// ``BoostLoginFlow``. If OwnID requires additional authentication, the flow may continue as login or registration,
/// depending on the current requirements. Registration completes with ``BoostFlowResponse/createPasskey(_:)`` and
/// includes passkey attestation proof values when available. Passkey registration can also return a successful
/// create-passkey response without proof values when local passkey creation is unavailable or fails, allowing the app
/// to continue its non-passkey registration path.
/// The flow updates the stored last user only after a successful login result that it completed itself, or after a
/// create-passkey result with a proof token.
///
/// User or owner cancellation settles as ``FlowResult/canceled(_:)``. Missing dependencies, unavailable required
/// operations, provider failures, account outcomes, and unresolved input settle as ``FlowResult/failure(_:)``.
public protocol BoostCreatePasskeyFlow: BoostFlow where ResponseType == BoostFlowResponse, Failure == BoostCreatePasskeyFlowFailure {
    /// Starts the Boost create-passkey flow with the given context.
    ///
    /// - Parameter context: Configuration for the flow.
    /// - Returns: A controller to await the result or cancel the flow.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is
    /// still active. Repeated calls on the same flow instance return the same controller and do not start a second run.
    func start(_ context: BoostFlowContext) -> any BoostCreatePasskeyFlowController
}

/// Failure payload returned by ``BoostLoginFlow``.
///
/// Every failure is terminal for the current login flow run. Use the concrete failure type to decide the next app-level
/// step, such as showing a final error, starting a new flow attempt, routing to registration, or inspecting app
/// integration. Use ``FlowFailure/errorCode`` only as a localization key.
public enum BoostLoginFlowFailure: FlowFailure, CustomStringConvertible {
    /// Input or OwnID context required before the first login operation could not be resolved.
    public enum Input: Sendable {
        /// - About: The flow could not resolve a usable login ID from the available context or access token.
        /// - End-user: End this sign-in attempt and let the user restart sign-in or enter a valid identifier in a new run.
        /// - Developer action: Check token contents, ``Context`` values, ``BoostFlowContext``, and login ID validation setup.
        /// - Diagnostics: `underlyingError` retains token or validation error context when available.
        case unresolvedLoginID(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    }

    /// Account state reported by login prevented the flow from completing.
    public enum Account: Sendable {
        /// - About: The account is blocked and cannot complete login.
        /// - End-user: End this sign-in attempt and direct the user to the app's recovery or support path.
        /// - Developer action: Treat as an expected business outcome unless provider data is inconsistent.
        case blocked(errorCode: ErrorCode, message: String)
        /// - About: The login path could not find an account for the resolved login ID.
        /// - End-user: End this sign-in attempt and direct the user to registration or another app-level path.
        /// - Developer action: Treat as an expected business outcome unless account provider data is inconsistent.
        case notFound(errorCode: ErrorCode, message: String)
    }

    /// Flow input or context resolution failed.
    case input(Input)
    /// Account state blocked login completion.
    case account(Account)
    /// - About: The flow could not satisfy server authentication requirements with the operations available in this SDK
    ///   instance and context.
    /// - End-user: End this sign-in attempt and offer a different app-level sign-in path or retry later.
    /// - Developer action: Check server auth requirements, configured providers, operation availability, and diagnostics in
    ///   `message` before starting a new attempt. The message may include skipped operation reasons.
    case insufficientAuth(errorCode: ErrorCode, message: String)
    /// - About: OwnID authentication succeeded, but the app's session-create provider failed.
    /// - End-user: End this sign-in attempt and show an app sign-in failure state.
    /// - Developer action: Inspect the app session-create provider, request context, and `underlyingError`. Avoid treating
    ///   this as failed OwnID authentication.
    case sessionCreationFailed(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    /// - About: A login flow operation could not run, was unavailable, or completed with failure.
    /// - End-user: End this sign-in attempt. The app may show a failure state, offer another app-level path, or let the
    ///   user start a new attempt.
    /// - Developer action: Do not continue this flow controller. Inspect `operationFailure` when present; otherwise inspect
    ///   `operationType`, `message`, and `underlyingError` before allowing a retry.
    /// - Diagnostics: `operationID` identifies a started child operation; `operationFailure` and `underlyingError` retain
    ///   child operation or runtime context when available.
    case operationFailed(
        operationType: OperationType,
        errorCode: ErrorCode,
        message: String,
        operationID: OperationID? = nil,
        operationFailure: (any OperationFailure)? = nil,
        underlyingError: (any Error & Sendable)? = nil
    )
    /// - About: The flow stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: End this sign-in attempt and show a generic failure state.
    /// - Developer action: Log flow context and `underlyingError`. Retry only by starting a new flow attempt after the
    ///   cause is understood or the user explicitly retries.
    case unexpected(errorCode: ErrorCode = .unknown, message: String, underlyingError: (any Error & Sendable)? = nil)

    private var payload: (ErrorCode, String) {
        switch self {
        case .input(let input):
            switch input {
            case .unresolvedLoginID(let errorCode, let message, _): return (errorCode, message)
            }
        case .account(let account):
            switch account {
            case .blocked(let errorCode, let message), .notFound(let errorCode, let message): return (errorCode, message)
            }
        case .insufficientAuth(let errorCode, let message),
            .sessionCreationFailed(let errorCode, let message, _),
            .operationFailed(_, let errorCode, let message, _, _, _),
            .unexpected(let errorCode, let message, _):
            return (errorCode, message)
        }
    }

    public var errorCode: ErrorCode { payload.0 }
    public var message: String { payload.1 }
    public var description: String {
        switch self {
        case .input(.unresolvedLoginID):
            return "Input.UnresolvedLoginID(errorCode=\(errorCode), message=\(message))"
        case .account(.blocked):
            return "Account.Blocked(errorCode=\(errorCode), message=\(message))"
        case .account(.notFound):
            return "Account.NotFound(errorCode=\(errorCode), message=\(message))"
        case .insufficientAuth:
            return "InsufficientAuth(errorCode=\(errorCode), message=\(message))"
        case .sessionCreationFailed:
            return "SessionCreationFailed(errorCode=\(errorCode), message=\(message))"
        case .operationFailed:
            return "OperationFailed(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Failure payload returned by ``BoostCreatePasskeyFlow``.
///
/// Every failure is terminal for the current create-passkey flow run. Some create-passkey path outcomes are still
/// successful even when local passkey attestation is unavailable or fails; in that case proof values are absent and the
/// app should continue using its non-passkey registration path.
public enum BoostCreatePasskeyFlowFailure: FlowFailure, CustomStringConvertible {
    /// Input or OwnID context required before a usable operation could not be resolved.
    public enum Input: Sendable {
        /// - About: The flow could not resolve a usable login ID from the available context or access token.
        /// - End-user: End this registration attempt and let the user restart or enter a valid identifier in a new run.
        /// - Developer action: Check token contents, ``Context`` values, ``BoostFlowContext``, and login ID validation setup.
        /// - Diagnostics: `underlyingError` retains token or validation error context when available.
        case unresolvedLoginID(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    }

    /// Account state reported by the create-passkey path.
    public enum Account: Sendable {
        /// - About: The resolved account is blocked and cannot continue.
        /// - End-user: End this attempt and direct the user to the app's recovery or support path.
        /// - Developer action: Treat as an expected business outcome unless provider data is inconsistent.
        case blocked(errorCode: ErrorCode, message: String)
        /// - About: The flow could not find an account for the resolved login ID in a path that requires an existing account.
        /// - End-user: End this attempt and route the user to the app's registration path or another identifier entry path.
        /// - Developer action: Treat as an expected account-state outcome unless provider data is inconsistent.
        case notFound(errorCode: ErrorCode, message: String)
    }

    /// Flow input or context resolution failed.
    case input(Input)
    /// Account state blocked create-passkey completion.
    case account(Account)
    /// - About: The flow could not satisfy server authentication requirements with the operations available in this SDK
    ///   instance and context.
    /// - End-user: End this attempt and offer a different sign-in or registration path, or retry later.
    /// - Developer action: Check server auth requirements, configured providers, operation availability, and diagnostics in
    ///   `message` before starting a new attempt. The message may include skipped operation reasons.
    case insufficientAuth(errorCode: ErrorCode, message: String)
    /// - About: OwnID authentication succeeded, but the app's session-create provider failed.
    /// - End-user: End this attempt and show an app sign-in failure state.
    /// - Developer action: Inspect the app session-create provider, request context, and `underlyingError`. Avoid treating
    ///   this as failed OwnID authentication.
    case sessionCreationFailed(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    /// - About: A required create-passkey flow operation could not run, was unavailable, or completed with failure.
    /// - End-user: End this attempt. The app may show a failure state, offer another app-level path, or let the user start
    ///   a new attempt.
    /// - Developer action: Do not continue this flow controller. Inspect `operationFailure` when present; otherwise inspect
    ///   `operationType`, `message`, and `underlyingError` before allowing a retry.
    /// - Diagnostics: `operationID` identifies a started child operation; `operationFailure` and `underlyingError` retain
    ///   child operation or runtime context when available.
    case operationFailed(
        operationType: OperationType,
        errorCode: ErrorCode,
        message: String,
        operationID: OperationID? = nil,
        operationFailure: (any OperationFailure)? = nil,
        underlyingError: (any Error & Sendable)? = nil
    )
    /// - About: The flow stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: End this attempt and show a generic failure state.
    /// - Developer action: Log flow context and `underlyingError`. Retry only by starting a new flow attempt after the
    ///   cause is understood or the user explicitly retries.
    case unexpected(errorCode: ErrorCode = .unknown, message: String, underlyingError: (any Error & Sendable)? = nil)

    private var payload: (ErrorCode, String) {
        switch self {
        case .input(let input):
            switch input {
            case .unresolvedLoginID(let errorCode, let message, _): return (errorCode, message)
            }
        case .account(let account):
            switch account {
            case .blocked(let errorCode, let message), .notFound(let errorCode, let message): return (errorCode, message)
            }
        case .insufficientAuth(let errorCode, let message),
            .sessionCreationFailed(let errorCode, let message, _),
            .operationFailed(_, let errorCode, let message, _, _, _),
            .unexpected(let errorCode, let message, _):
            return (errorCode, message)
        }
    }

    public var errorCode: ErrorCode { payload.0 }
    public var message: String { payload.1 }
    public var description: String {
        switch self {
        case .input(.unresolvedLoginID):
            return "Input.UnresolvedLoginID(errorCode=\(errorCode), message=\(message))"
        case .account(.blocked):
            return "Account.Blocked(errorCode=\(errorCode), message=\(message))"
        case .account(.notFound):
            return "Account.NotFound(errorCode=\(errorCode), message=\(message))"
        case .insufficientAuth:
            return "InsufficientAuth(errorCode=\(errorCode), message=\(message))"
        case .sessionCreationFailed:
            return "SessionCreationFailed(errorCode=\(errorCode), message=\(message))"
        case .operationFailed:
            return "OperationFailed(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

extension BoostCreatePasskeyFlow {
    /// Starts the Boost create-passkey flow with a default empty context.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is
    /// still active.
    public func start() -> any BoostCreatePasskeyFlowController {
        start(.empty)
    }
}
