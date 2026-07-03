import Foundation

/// Verifies user ownership of an email address via a one-time code.
///
/// Call ``OperationCapability/start(params:)`` to launch one operation run. The returned controller also conforms to
/// ``EmailVerificationOperationController``; keep it while the run is active, use ``EmailVerificationOperationController/stateStream()``
/// for lifecycle and UI state, and call ``OperationController/abort(reason:)`` to stop the run with an explicit ``Reason``.
///
/// Explicit ``EmailVerificationOperationParams`` values take precedence over values from the current OwnID context. If
/// ``EmailVerificationOperationParams/loginID`` or ``EmailVerificationOperationParams/accessToken`` is `nil`, the operation
/// uses the matching context value when available. An access token is enough to start without a login ID. When a login ID
/// is resolved, it must be ``LoginIDType/email``, or ``LoginIDType/userName`` with a non-empty
/// ``EmailVerificationOperationParams/loginIDHintID`` that identifies the selected email channel. Unsupported input is
/// reported through ``OperationCapability/availability(params:)`` as unavailable and through
/// ``OperationCapability/start(params:)`` as ``OperationResult/failure(_:)``.
///
/// The operation requests OTP verification. If OwnID returns a challenge without OTP support, the run completes with
/// ``OperationResult/failure(_:)``. In the active state, ``EmailVerificationOperationState/active(uiState:apiController:)``
/// carries the current challenge, loading/error state, and callbacks for code entry, resend, cancel, and "not you". The
/// challenge includes the email destination for the code. The active API controller is exposed for advanced integrations
/// that need direct access to the challenge controller for the same operation run.
///
/// A correct code completes with ``OperationResult/success(_:)`` containing ``AccessOrProofToken``, which is either
/// ``AccessToken`` or ``ProofToken``. A wrong code keeps the run active and updates the UI state with an error. Reaching
/// the resend limit keeps the run active and marks resend unavailable for the current challenge. Terminal challenge,
/// access, input, integration, and unexpected failures complete with ``OperationResult/failure(_:)``. User cancel, "not
/// you", ``OperationController/abort(reason:)``, lifecycle cancellation, and challenge timeout complete with
/// ``OperationResult/canceled(_:)``; when possible, an active challenge is canceled as part of that settlement.
///
/// If no UI implementation is registered, startup fails and the operation completes with
/// ``OperationResult/failure(_:)``.
public protocol EmailVerificationOperation: OperationCapability, Sendable
where
    Params == EmailVerificationOperationParams,
    Result == AccessOrProofToken,
    Failure == EmailVerificationOperationFailure
{}

/// Parameters for ``EmailVerificationOperation``.
///
/// All parameters default to `nil`. Non-`nil` values take precedence over the current OwnID context.
public struct EmailVerificationOperationParams: CapabilityParams, Sendable {
    /// The email address to verify, or a username when ``loginIDHintID`` identifies an associated email channel.
    /// Defaults to `nil`.
    public let loginID: LoginID?
    /// An optional hint identifier for the email channel associated with ``loginID``. Required and non-empty when
    /// ``loginID`` is ``LoginIDType/userName``. Defaults to `nil`.
    public let loginIDHintID: String?
    /// An existing access token, if available. When `nil`, the current OwnID context access token is used if available.
    /// Defaults to `nil`.
    public let accessToken: AccessToken?
    /// Best-effort callback invoked when the user interacts with the UI (code entry, resend, cancel, or "not you").
    /// Receives the ``OperationID`` and does not control operation settlement. Defaults to `nil`.
    public let onUIClick: (@Sendable (OperationID) -> Void)?
    internal let traceParent: String?

    /// Creates email verification parameters.
    ///
    /// - Parameters:
    ///   - loginID: Email address to verify, or a username when `loginIDHintID` identifies an associated email channel.
    ///     Defaults to `nil`.
    ///   - loginIDHintID: An optional hint identifier for the email channel associated with `loginID`. Required and
    ///     non-empty when `loginID` is ``LoginIDType/userName``. Defaults to `nil`.
    ///   - accessToken: Existing access token, if available. When `nil`, the current OwnID context access token is used if
    ///     available. Defaults to `nil`.
    ///   - onUIClick: Best-effort callback invoked on UI interactions (code entry, resend, cancel, or "not you"). Defaults
    ///     to `nil`.
    public init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        onUIClick: (@Sendable (OperationID) -> Void)? = nil
    ) {
        self.loginID = loginID
        self.loginIDHintID = loginIDHintID
        self.accessToken = accessToken
        self.onUIClick = onUIClick
        self.traceParent = nil
    }

    internal init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        onUIClick: (@Sendable (OperationID) -> Void)? = nil,
        traceParent: String? = nil
    ) {
        self.loginID = loginID
        self.loginIDHintID = loginIDHintID
        self.accessToken = accessToken
        self.onUIClick = onUIClick
        self.traceParent = traceParent
    }
}

/// Controller for one running ``EmailVerificationOperation``.
///
/// ``start(params:)`` returns a general ``OperationController``. When host-managed UI needs access to state updates, cast
/// that controller to ``EmailVerificationOperationController`` and observe ``stateStream()``.
public protocol EmailVerificationOperationController: OperationController<AccessOrProofToken, EmailVerificationOperationFailure> {
    /// Emits state transitions for the running email verification operation on the main actor.
    @MainActor func stateStream() -> AsyncStream<EmailVerificationOperationState>
}

/// State emitted by ``EmailVerificationOperationController/stateStream()``.
///
/// States progress from ``created`` through ``preparing(params:)`` and ``active(uiState:apiController:)`` to
/// ``completed(result:)`` with an ``OperationResult`` containing ``AccessOrProofToken``.
public enum EmailVerificationOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// The operation is initializing with the given params.
    case preparing(params: EmailVerificationOperationParams)
    /// The verification UI is visible. `uiState` carries the selected challenge and UI callbacks; `apiController` owns
    /// the selected challenge for this operation run.
    case active(uiState: EmailVerificationUIState, apiController: any EmailVerificationAPIController)
    /// The operation finished with a success token, cancellation reason, or typed failure.
    case completed(result: OperationResult<AccessOrProofToken, EmailVerificationOperationFailure>)
}

extension EmailVerificationOperationState: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.created, .created):
            return true
        case (.preparing(let lp), .preparing(let rp)):
            return lp.loginID == rp.loginID
                && lp.loginIDHintID == rp.loginIDHintID
        case (.active(let lu, _), .active(let ru, _)):
            return lu == ru
        case (.completed, .completed):
            return true
        default:
            return false
        }
    }
}

/// Failure payload returned by ``EmailVerificationOperation``.
///
/// Every failure is terminal for the current operation run. Recoverable wrong-code responses stay in active UI state
/// and are not emitted as failures. Branch on the category to decide whether to ask for corrected input, stop the OTP
/// challenge, offer another auth path, or fix integration. Use ``OperationFailure/errorCode`` as a localization key;
/// use `apiFailure`, `underlyingError`, `challengeID`, `loginID`, `capability`, and `regex` for diagnostics.
public enum EmailVerificationOperationFailure: OperationFailure, CustomStringConvertible {
    /// Missing, invalid, or unsupported email verification input.
    public enum Input: Sendable {
        /// - About: The operation could not resolve either an access token or an email login ID to start verification.
        /// - End-user: Ask the user to enter an email address or use another available authentication path.
        /// - Developer action: Pass an email ``LoginID`` or ``AccessToken``, or provide one through OwnID context.
        case missingLoginIDOrAccessToken(errorCode: ErrorCode, message: String)
        /// - About: The resolved login ID is not an email address, or is a username without an email channel hint.
        /// - End-user: Ask the user for an email address or restart this step.
        /// - Developer action: Start email verification with ``LoginIDType/email``, or ``LoginIDType/userName`` plus
        ///   ``EmailVerificationOperationParams/loginIDHintID`` from the server-recommended email channel.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The resolved email login ID failed validation.
        /// - End-user: Ask the user to correct the email address.
        /// - Developer action: Keep client-side validation aligned with OwnID configuration. Use `regex` and
        ///   `apiFailure` only for diagnostics.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The verification request was rejected as invalid.
        /// - End-user: No direct user action unless the app can collect corrected input.
        /// - Developer action: Inspect the provided params, current challenge state, and `apiFailure`.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Account or access-token policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The account associated with the verification request was not found.
        /// - End-user: Route to registration, account recovery, or another app-level path.
        /// - Developer action: Treat as an expected account-state outcome unless provider data is inconsistent.
        case userNotFound(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The caller is not allowed to start or complete email verification in this context.
        /// - End-user: Explain that the requested action is unavailable or offer another path.
        /// - Developer action: Check access token claims, app policy, operation requirements, and `apiFailure`.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// OTP challenge lifecycle failures.
    public enum Challenge: Sendable {
        /// - About: The active email verification challenge limit was reached.
        /// - End-user: End this verification attempt and let the user retry later or choose another method.
        /// - Developer action: Do not create another challenge immediately; inspect rate-limit and challenge policy diagnostics.
        case maximumChallengesReached(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The email verification challenge is invalid, expired, or no longer usable.
        /// - End-user: Ask the user to start a new verification attempt.
        /// - Developer action: Treat the current `challengeID` as terminal and start a new challenge before retrying.
        case invalid(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
        /// - About: The email verification challenge reached its attempt limit.
        /// - End-user: End this challenge and let the user restart verification only when appropriate.
        /// - Developer action: Stop the current `challengeID`; start a new operation/controller for a fresh attempt.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, backend, provider, or platform integration failures.
    public enum Integration: Sendable {
        /// - About: The requested email verification channel is unavailable for the resolved login ID.
        /// - End-user: Offer another authentication path or ask the user to use a different identifier.
        /// - Developer action: Inspect login ID configuration, channel availability, and `apiFailure`.
        case missingChannel(errorCode: ErrorCode, message: String, loginID: LoginID, apiFailure: (any APIFailure)? = nil)
        /// - About: A configured backend/provider dependency failed while processing email verification.
        /// - End-user: Show a temporary failure state or offer another available path.
        /// - Developer action: Log provider context, inspect `apiFailure`, and avoid aggressive automatic retries.
        case providerFailed(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: A provider capability required by email verification is not configured.
        /// - End-user: No direct user action. Offer another available path when possible.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The email verification UI failed before the operation could complete.
        /// - End-user: Show a generic unavailable state or let the user retry opening verification.
        /// - Developer action: Inspect UI setup, window/presentation availability, and `underlyingError` for the concrete
        ///   UI failure.
        case ui(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    }

    /// Login ID, access token, or request input cannot be used.
    case input(Input)
    /// Account or access-token policy blocked verification.
    case access(Access)
    /// OTP challenge creation or completion failed.
    case challenge(Challenge)
    /// SDK, app, backend, provider, or UI integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic verification failure state and let the user start a new attempt when appropriate.
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
            case .missingLoginIDOrAccessToken(let errorCode, let message),
                .unsupportedLoginIDType(let errorCode, let message, _),
                .invalidLoginID(let errorCode, let message, _, _, _),
                .invalidRequest(let errorCode, let message, _):
                return (errorCode, message)
            }
        case .access(let access):
            switch access {
            case .userNotFound(let errorCode, let message, _),
                .forbidden(let errorCode, let message, _):
                return (errorCode, message)
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
            case .missingChannel(let errorCode, let message, _, _),
                .providerFailed(let errorCode, let message, _),
                .missingProvider(let errorCode, let message, _, _),
                .ui(let errorCode, let message, _):
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
            case .unsupportedLoginIDType:
                return "Input.UnsupportedLoginIDType(errorCode=\(errorCode), message=\(message))"
            case .invalidLoginID:
                return "Input.InvalidLoginID(errorCode=\(errorCode), message=\(message))"
            case .invalidRequest:
                return "Input.InvalidRequest(errorCode=\(errorCode), message=\(message))"
            }
        case .access(let access):
            switch access {
            case .userNotFound:
                return "Access.UserNotFound(errorCode=\(errorCode), message=\(message))"
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
            case .missingChannel:
                return "Integration.MissingChannel(errorCode=\(errorCode), message=\(message))"
            case .providerFailed:
                return "Integration.ProviderFailed(errorCode=\(errorCode), message=\(message))"
            case .missingProvider:
                return "Integration.MissingProvider(errorCode=\(errorCode), message=\(message))"
            case .ui:
                return "Integration.UI(errorCode=\(errorCode), message=\(message))"
            }
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Verifies user ownership of a phone number via a one-time code.
///
/// Call ``OperationCapability/start(params:)`` to launch one operation run. The returned controller also conforms to
/// ``PhoneVerificationOperationController``; keep it while the run is active, use ``PhoneVerificationOperationController/stateStream()``
/// for lifecycle and UI state, and call ``OperationController/abort(reason:)`` to stop the run with an explicit ``Reason``.
///
/// Explicit ``PhoneVerificationOperationParams`` values take precedence over values from the current OwnID context. If
/// ``PhoneVerificationOperationParams/loginID`` or ``PhoneVerificationOperationParams/accessToken`` is `nil`, the operation
/// uses the matching context value when available. An access token is enough to start without a login ID. When a login ID
/// is resolved, it must be ``LoginIDType/phoneNumber``, or ``LoginIDType/userName`` with a non-empty
/// ``PhoneVerificationOperationParams/loginIDHintID`` that identifies the selected phone channel. Unsupported input is
/// reported through ``OperationCapability/availability(params:)`` as unavailable and through
/// ``OperationCapability/start(params:)`` as ``OperationResult/failure(_:)``.
///
/// The operation requests OTP verification. If OwnID returns a challenge without OTP support, the run completes with
/// ``OperationResult/failure(_:)``. In the active state, ``PhoneVerificationOperationState/active(uiState:apiController:)``
/// carries the current challenge, loading/error state, and callbacks for code entry, resend, cancel, and "not you". The
/// challenge includes the phone destination for the code. The active API controller is exposed for advanced integrations
/// that need direct access to the challenge controller for the same operation run.
///
/// A correct code completes with ``OperationResult/success(_:)`` containing ``AccessOrProofToken``, which is either
/// ``AccessToken`` or ``ProofToken``. A wrong code keeps the run active and updates the UI state with an error. Reaching
/// the resend limit keeps the run active and marks resend unavailable for the current challenge. Terminal challenge,
/// access, input, integration, and unexpected failures complete with ``OperationResult/failure(_:)``. User cancel, "not
/// you", ``OperationController/abort(reason:)``, lifecycle cancellation, and challenge timeout complete with
/// ``OperationResult/canceled(_:)``; when possible, an active challenge is canceled as part of that settlement.
///
/// If no UI implementation is registered, startup fails and the operation completes with
/// ``OperationResult/failure(_:)``.
public protocol PhoneVerificationOperation: OperationCapability, Sendable
where
    Params == PhoneVerificationOperationParams,
    Result == AccessOrProofToken,
    Failure == PhoneVerificationOperationFailure
{}

/// Parameters for ``PhoneVerificationOperation``.
///
/// All parameters default to `nil`. Non-`nil` values take precedence over the current OwnID context.
public struct PhoneVerificationOperationParams: CapabilityParams {
    /// The phone number to verify, or a username when ``loginIDHintID`` identifies an associated phone channel.
    /// Defaults to `nil`.
    public let loginID: LoginID?
    /// An optional hint identifier for the phone channel associated with ``loginID``. Required and non-empty when
    /// ``loginID`` is ``LoginIDType/userName``. Defaults to `nil`.
    public let loginIDHintID: String?
    /// An existing access token, if available. When `nil`, the current OwnID context access token is used if available.
    /// Defaults to `nil`.
    public let accessToken: AccessToken?
    /// Best-effort callback invoked when the user interacts with the UI (code entry, resend, cancel, or "not you").
    /// Receives the ``OperationID`` and does not control operation settlement. Defaults to `nil`.
    public let onUIClick: (@Sendable (OperationID) -> Void)?
    internal let traceParent: String?

    /// Creates phone verification parameters.
    ///
    /// - Parameters:
    ///   - loginID: Phone number to verify, or a username when `loginIDHintID` identifies an associated phone channel.
    ///     Defaults to `nil`.
    ///   - loginIDHintID: An optional hint identifier for the phone channel associated with `loginID`. Required and
    ///     non-empty when `loginID` is ``LoginIDType/userName``. Defaults to `nil`.
    ///   - accessToken: Existing access token, if available. When `nil`, the current OwnID context access token is used if
    ///     available. Defaults to `nil`.
    ///   - onUIClick: Best-effort callback invoked on UI interactions (code entry, resend, cancel, or "not you"). Defaults
    ///     to `nil`.
    public init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        onUIClick: (@Sendable (OperationID) -> Void)? = nil
    ) {
        self.loginID = loginID
        self.loginIDHintID = loginIDHintID
        self.accessToken = accessToken
        self.onUIClick = onUIClick
        self.traceParent = nil
    }

    internal init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        onUIClick: (@Sendable (OperationID) -> Void)? = nil,
        traceParent: String? = nil
    ) {
        self.loginID = loginID
        self.loginIDHintID = loginIDHintID
        self.accessToken = accessToken
        self.onUIClick = onUIClick
        self.traceParent = traceParent
    }
}

/// Controller for one running ``PhoneVerificationOperation``.
///
/// ``start(params:)`` returns a general ``OperationController``. When host-managed UI needs access to state updates, cast
/// that controller to ``PhoneVerificationOperationController`` and observe ``stateStream()``.
public protocol PhoneVerificationOperationController: OperationController<AccessOrProofToken, PhoneVerificationOperationFailure> {
    /// Emits state transitions for the running phone verification operation on the main actor.
    @MainActor func stateStream() -> AsyncStream<PhoneVerificationOperationState>
}

/// State emitted by ``PhoneVerificationOperationController/stateStream()``.
///
/// States progress from ``created`` through ``preparing(params:)`` and ``active(uiState:apiController:)`` to
/// ``completed(result:)`` with an ``OperationResult`` containing ``AccessOrProofToken``.
public enum PhoneVerificationOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// The operation is initializing with the given params.
    case preparing(params: PhoneVerificationOperationParams)
    /// The verification UI is visible. `uiState` carries the selected challenge and UI callbacks; `apiController` owns
    /// the selected challenge for this operation run.
    case active(uiState: PhoneVerificationUIState, apiController: any PhoneVerificationAPIController)
    /// The operation finished with a success token, cancellation reason, or typed failure.
    case completed(result: OperationResult<AccessOrProofToken, PhoneVerificationOperationFailure>)
}

extension PhoneVerificationOperationState: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.created, .created):
            return true
        case (.preparing(let lp), .preparing(let rp)):
            return lp.loginID == rp.loginID
                && lp.loginIDHintID == rp.loginIDHintID
        case (.active(let lu, _), .active(let ru, _)):
            return lu == ru
        case (.completed, .completed):
            return true
        default:
            return false
        }
    }
}

/// Failure payload returned by ``PhoneVerificationOperation``.
///
/// Every failure is terminal for the current operation run. Recoverable wrong-code responses stay in active UI state
/// and are not emitted as failures. Branch on the category to decide whether to ask for corrected input, stop the OTP
/// challenge, offer another auth path, or fix integration. Use ``OperationFailure/errorCode`` as a localization key;
/// use `apiFailure`, `underlyingError`, `challengeID`, `loginID`, `capability`, and `regex` for diagnostics.
public enum PhoneVerificationOperationFailure: OperationFailure, CustomStringConvertible {
    /// Missing, invalid, or unsupported phone verification input.
    public enum Input: Sendable {
        /// - About: The operation could not resolve either an access token or a phone login ID to start verification.
        /// - End-user: Ask the user to enter a phone number or use another available authentication path.
        /// - Developer action: Pass a phone ``LoginID`` or ``AccessToken``, or provide one through OwnID context.
        case missingLoginIDOrAccessToken(errorCode: ErrorCode, message: String)
        /// - About: The resolved login ID is not a phone number, or is a username without a phone channel hint.
        /// - End-user: Ask the user for a phone number or restart this step.
        /// - Developer action: Start phone verification with ``LoginIDType/phoneNumber``, or ``LoginIDType/userName`` plus
        ///   ``PhoneVerificationOperationParams/loginIDHintID`` from the server-recommended phone channel.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The resolved phone login ID failed validation.
        /// - End-user: Ask the user to correct the phone number.
        /// - Developer action: Keep client-side validation aligned with OwnID configuration. Use `regex` and
        ///   `apiFailure` only for diagnostics.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The verification request was rejected as invalid.
        /// - End-user: No direct user action unless the app can collect corrected input.
        /// - Developer action: Inspect the provided params, current challenge state, and `apiFailure`.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Account or access-token policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The account associated with the verification request was not found.
        /// - End-user: Route to registration, account recovery, or another app-level path.
        /// - Developer action: Treat as an expected account-state outcome unless provider data is inconsistent.
        case userNotFound(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The caller is not allowed to start or complete phone verification in this context.
        /// - End-user: Explain that the requested action is unavailable or offer another path.
        /// - Developer action: Check access token claims, app policy, operation requirements, and `apiFailure`.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// OTP challenge lifecycle failures.
    public enum Challenge: Sendable {
        /// - About: The active phone verification challenge limit was reached.
        /// - End-user: End this verification attempt and let the user retry later or choose another method.
        /// - Developer action: Do not create another challenge immediately; inspect rate-limit and challenge policy diagnostics.
        case maximumChallengesReached(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The phone verification challenge is invalid, expired, or no longer usable.
        /// - End-user: Ask the user to start a new verification attempt.
        /// - Developer action: Treat the current `challengeID` as terminal and start a new challenge before retrying.
        case invalid(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
        /// - About: The phone verification challenge reached its attempt limit.
        /// - End-user: End this challenge and let the user restart verification only when appropriate.
        /// - Developer action: Stop the current `challengeID`; start a new operation/controller for a fresh attempt.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, backend, provider, or platform integration failures.
    public enum Integration: Sendable {
        /// - About: The requested phone verification channel is unavailable for the resolved login ID.
        /// - End-user: Offer another authentication path or ask the user to use a different identifier.
        /// - Developer action: Inspect login ID configuration, channel availability, and `apiFailure`.
        case missingChannel(errorCode: ErrorCode, message: String, loginID: LoginID, apiFailure: (any APIFailure)? = nil)
        /// - About: A configured backend/provider dependency failed while processing phone verification.
        /// - End-user: Show a temporary failure state or offer another available path.
        /// - Developer action: Log provider context, inspect `apiFailure`, and avoid aggressive automatic retries.
        case providerFailed(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: A provider capability required by phone verification is not configured.
        /// - End-user: No direct user action. Offer another available path when possible.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The phone verification UI failed before the operation could complete.
        /// - End-user: Show a generic unavailable state or let the user retry opening verification.
        /// - Developer action: Inspect UI setup, window/presentation availability, and `underlyingError` for the concrete
        ///   UI failure.
        case ui(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    }

    /// Login ID, access token, or request input cannot be used.
    case input(Input)
    /// Account or access-token policy blocked verification.
    case access(Access)
    /// OTP challenge creation or completion failed.
    case challenge(Challenge)
    /// SDK, app, backend, provider, or UI integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic verification failure state and let the user start a new attempt when appropriate.
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
            case .missingLoginIDOrAccessToken(let errorCode, let message),
                .unsupportedLoginIDType(let errorCode, let message, _),
                .invalidLoginID(let errorCode, let message, _, _, _),
                .invalidRequest(let errorCode, let message, _):
                return (errorCode, message)
            }
        case .access(let access):
            switch access {
            case .userNotFound(let errorCode, let message, _),
                .forbidden(let errorCode, let message, _):
                return (errorCode, message)
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
            case .missingChannel(let errorCode, let message, _, _),
                .providerFailed(let errorCode, let message, _),
                .missingProvider(let errorCode, let message, _, _),
                .ui(let errorCode, let message, _):
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
            case .unsupportedLoginIDType:
                return "Input.UnsupportedLoginIDType(errorCode=\(errorCode), message=\(message))"
            case .invalidLoginID:
                return "Input.InvalidLoginID(errorCode=\(errorCode), message=\(message))"
            case .invalidRequest:
                return "Input.InvalidRequest(errorCode=\(errorCode), message=\(message))"
            }
        case .access(let access):
            switch access {
            case .userNotFound:
                return "Access.UserNotFound(errorCode=\(errorCode), message=\(message))"
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
            case .missingChannel:
                return "Integration.MissingChannel(errorCode=\(errorCode), message=\(message))"
            case .providerFailed:
                return "Integration.ProviderFailed(errorCode=\(errorCode), message=\(message))"
            case .missingProvider:
                return "Integration.MissingProvider(errorCode=\(errorCode), message=\(message))"
            case .ui:
                return "Integration.UI(errorCode=\(errorCode), message=\(message))"
            }
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
