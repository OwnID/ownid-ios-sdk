import Foundation

/// Successful passkey-enroll response.
public struct PasskeyEnrollFlowResponse: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The enrolled user's login identifier.
    public let loginID: LoginID

    public init(loginID: LoginID) {
        self.loginID = loginID
    }

    /// A debug string for the passkey-enroll response.
    public var description: String {
        "PasskeyEnrollFlowResponse(loginID: \(loginID))"
    }
}

/// Controls a running passkey enrollment flow.
///
/// - Call ``whenSettled()`` to await the final ``FlowResult``.
/// - Use ``abort(reason:)`` for semantic cancellation with an explicit ``Reason``.
///
/// The caller owns this controller. Keep it strongly referenced while the flow is active, and abort it if the owner
/// is torn down before settlement.
///
/// Cancellation is best-effort. Calling ``abort(reason:)`` after settlement is safe and has no effect.
public protocol PasskeyEnrollController: Sendable {
    /// Requests flow cancellation with an explicit `reason`.
    ///
    /// Use this API when cancellation semantics are meaningful to the caller and should be reflected in the terminal
    /// result.
    ///
    /// If the flow is already settled, this call has no effect.
    func abort(reason: Reason)
    /// Awaits the flow's completion and returns the ``FlowResult``.
    func whenSettled() async -> FlowResult<PasskeyEnrollFlowResponse, PasskeyEnrollFlowFailure>
}

extension FlowController: PasskeyEnrollController where Success == PasskeyEnrollFlowResponse, Failure == PasskeyEnrollFlowFailure {}

/// Flow that enrolls a passkey for an already-authenticated user.
///
/// The flow requires an access token from ``PasskeyEnrollFlowContext`` or the current ``Context``. The access token
/// is used to resolve the enrolled ``LoginID`` and to authorize passkey enrollment for that user.
/// It does not sign the user in, create an app session, refresh app tokens, or persist app authentication state.
///
/// If a proof token is provided, the flow skips passkey attestation and calls the enroll API; otherwise it runs
/// passkey attestation followed by server-side enrollment. In the attestation branch, the
/// ``AttestationResponse/proofToken`` is consumed by the flow for enrollment and ``AttestationResponse/ownIdData`` is
/// not returned to the caller. Use the lower-level attestation API or operation when the app must receive `ownIdData`
/// at its own registration boundary.
///
/// The ``PasskeyEnrollFlowContext/headless`` flag is reserved and currently has no observable effect. It does not
/// suppress platform passkey UI when local attestation is required. Availability checks follow the same branch: with a
/// proof token they check enrollment readiness, and without one they check local passkey creation readiness.
///
/// - Check ``isAvailable(params:)`` before starting to verify the required access-token path and passkey enrollment support.
/// - Call ``start(_:)`` with an optional ``PasskeyEnrollFlowContext`` to begin enrollment.
/// - The returned ``PasskeyEnrollController`` delivers one terminal ``FlowResult``: ``FlowResult/success(_:)`` means
///   the passkey was enrolled for ``PasskeyEnrollFlowResponse/loginID``, ``FlowResult/canceled(_:)`` means the run
///   stopped with a ``Reason``, and ``FlowResult/failure(_:)`` carries a typed ``PasskeyEnrollFlowFailure``.
///
/// The caller owns the returned controller. Keep it strongly referenced while the flow is active.
///
/// Use ``PasskeyEnrollController/abort(reason:)`` for semantic cancellation when you have an explicit reason that
/// should be propagated to the terminal result. If the owner is torn down while the flow is still active, abort the
/// flow with an appropriate ``Reason``.
///
/// Accessed via `OwnID.headless.passkeys.enroll`.
public protocol PasskeyEnrollFlow: FlowCapability, Sendable {
    /// Returns whether passkey enrollment can start with the given params.
    ///
    /// Pass `nil` to check availability without explicit parameters. When provided, `params` must be a
    /// ``PasskeyEnrollFlowContext``.
    ///
    /// If unavailable, the result carries a human-readable message explaining what the integrator needs to provide
    /// or change before calling ``start(_:)``. Passing ``PasskeyEnrollFlowContext/proofToken`` checks the server
    /// enrollment path; omitting it checks whether local passkey creation can start.
    func availability(params: (any CapabilityParams)?) async -> Availability

    /// Starts passkey enrollment with the given context.
    ///
    /// - Parameter context: Optional per-run configuration. Pass `nil` to use the current ``Context`` access token,
    ///   run local passkey attestation, and omit the reserved headless flag.
    /// - Returns: A controller to await the result or cancel the flow.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is
    /// still active. Repeated calls on the same flow instance return the same controller and do not start a second run.
    func start(_ context: PasskeyEnrollFlowContext?) -> any PasskeyEnrollController
}

extension PasskeyEnrollFlow {
    /// Returns `true` when passkey enrollment can start with the given params.
    ///
    /// Use ``availability(params:)`` when the unavailable reason is needed.
    public func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        if case .available = await availability(params: params) { return true }
        return false
    }

    /// Starts passkey enrollment with no context.
    ///
    /// The caller owns the returned controller and should abort it when the owner lifecycle ends while the flow is still active.
    public func start() -> any PasskeyEnrollController {
        start(nil)
    }
}

/// Failure payload returned by ``PasskeyEnrollFlow``.
///
/// Every failure is terminal for the current passkey enrollment flow run. The flow requires an access token, resolves
/// the login ID from it, optionally runs passkey attestation to obtain a proof token, and then runs passkey enrollment.
/// Canceled runs are reported as ``FlowResult/canceled(_:)``, not as this failure type.
public enum PasskeyEnrollFlowFailure: FlowFailure, CustomStringConvertible {
    /// Flow input or context resolution failed before enrollment could start.
    public enum Input: Sendable {
        /// - About: No access token was available from flow params or current OwnID context.
        /// - End-user: End this enrollment attempt and ask the user to sign in before starting a new passkey enrollment.
        /// - Developer action: Start the flow only after authentication, pass ``PasskeyEnrollFlowContext/accessToken``,
        ///   or provide an access token through OwnID context.
        case missingAccessToken(errorCode: ErrorCode, message: String)
        /// - About: The flow could not resolve a usable login ID from the available access token.
        /// - End-user: End this enrollment attempt and ask the user to sign in again before retrying.
        /// - Developer action: Check token contents, token forwarding, and login ID validation setup.
        /// - Diagnostics: `underlyingError` retains token or validation error context when available.
        case unresolvedLoginID(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    }

    /// Flow input or OwnID context required before enrollment could not be resolved.
    case input(Input)
    /// - About: Passkey attestation or server-side passkey enrollment could not run, was unavailable, or completed with
    ///   failure.
    /// - End-user: End this enrollment attempt. The app may show a failure state, offer another account security path, or
    ///   let the user start a new attempt.
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
    /// - End-user: End this enrollment attempt and show a generic enrollment failure state.
    /// - Developer action: Log flow context and `underlyingError`. If `message` mentions a missing proof token, inspect
    ///   the preceding passkey attestation path before starting a new attempt.
    case unexpected(errorCode: ErrorCode = .unknown, message: String, underlyingError: (any Error & Sendable)? = nil)

    private var payload: (ErrorCode, String) {
        switch self {
        case .input(let input):
            switch input {
            case .missingAccessToken(let errorCode, let message), .unresolvedLoginID(let errorCode, let message, _):
                return (errorCode, message)
            }
        case .operationFailed(_, let errorCode, let message, _, _, _),
            .unexpected(let errorCode, let message, _):
            return (errorCode, message)
        }
    }

    public var errorCode: ErrorCode { payload.0 }
    public var message: String { payload.1 }
    public var description: String {
        switch self {
        case .input(.missingAccessToken):
            return "Input.MissingAccessToken(errorCode=\(errorCode), message=\(message))"
        case .input(.unresolvedLoginID):
            return "Input.UnresolvedLoginID(errorCode=\(errorCode), message=\(message))"
        case .operationFailed:
            return "OperationFailed(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
