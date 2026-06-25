import Foundation

/// Creates (registers) a new passkey for the user.
///
/// This operation owns the full SDK-managed passkey attestation lifecycle: it starts an OwnID challenge, presents the
/// platform passkey UI through the registered ``PasskeyProtocol`` capability, verifies the platform attestation result,
/// and settles the returned ``OperationController``. Apps that want to own the platform passkey UI should use the
/// direct passkey API instead of this operation.
///
/// Explicit ``PasskeyAttestationOperationParams`` values take precedence over the current OwnID context. If
/// ``PasskeyAttestationOperationParams/accessToken`` or the context access token is available,
/// ``PasskeyAttestationOperationParams/loginID`` may be omitted. If no access token is available, the operation
/// requires a login ID from params or the current context; context login ID resolution can produce typed input or
/// integration failures.
///
/// The platform passkey prompt is owned by AuthenticationServices. The SDK supplies the current presentation context
/// through the registered passkey capability and converts the resulting passkey outcome into operation settlement:
/// successful attestation returns an ``AttestationResponse``, user or system cancellation returns
/// ``OperationResult/canceled(_:)``, and platform or provider failures return ``OperationResult/failure(_:)``. The
/// success payload contains OwnID registration data, including the proof token used by the app's registration boundary.
///
/// The returned controller represents one operation run and settles once. Keep it strongly referenced while the
/// operation is active. Calling ``OperationController/abort(reason:)`` before settlement cancels the active operation
/// with the supplied ``Reason``; when a server challenge is active, cancellation is also reported to OwnID on a
/// best-effort basis. If the challenge provides a timeout, the operation cancels with ``Reason/timeout`` after it
/// elapses. Repeated starts on the same operation object return the same controller and do not create a new passkey
/// prompt.
///
/// Requires version 16+ with passkey capabilities registered. ``OperationCapability/availability(params:)`` and
/// ``OperationCapability/isAvailable(params:)`` are preflight checks for registered dependencies and resolvable login
/// ID/access token input; ``OperationCapability/start(params:)`` revalidates the same contract and may still settle
/// with a typed failure or cancellation if runtime state changes.
public protocol PasskeyAttestationOperation: OperationCapability, Sendable
where
    Params == PasskeyAttestationOperationParams,
    Result == AttestationResponse,
    Failure == PasskeyAttestationOperationFailure
{}

/// Parameters for ``PasskeyAttestationOperation``.
///
/// Explicit values take precedence over the current OwnID context. A resolved access token can identify the
/// attestation request without a login ID.
public struct PasskeyAttestationOperationParams: CapabilityParams, Sendable {
    /// The user's login identifier. When `nil`, the current OwnID context login ID is used if available and no access
    /// token is available. Defaults to `nil`.
    public let loginID: LoginID?
    /// An existing access token identifying the user. When `nil`, the current OwnID context access token is used if
    /// available. Defaults to `nil`.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    /// Creates passkey attestation parameters.
    ///
    /// - Parameters:
    ///   - loginID: User login identifier. Defaults to `nil`.
    ///   - accessToken: Existing access token identifying the user. Defaults to `nil`.
    public init(loginID: LoginID? = nil, accessToken: AccessToken? = nil) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.traceParent = nil
    }

    internal init(loginID: LoginID? = nil, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controller for one started ``PasskeyAttestationOperation``.
///
/// The controller settles once with ``AttestationResponse``, ``OperationResult/canceled(_:)``, or
/// ``PasskeyAttestationOperationFailure``.
public typealias PasskeyAttestationOperationController = any OperationController<AttestationResponse, PasskeyAttestationOperationFailure>

/// State value used by the passkey attestation runtime.
///
/// States progress from ``created`` through ``preparing`` and ``active(apiController:)`` to ``completed(result:)`` with
/// an ``OperationResult`` containing an ``AttestationResponse``. The active state's direct API controller is exposed as
/// a state value for SDK UI binding; app code should settle the operation through the operation controller.
public enum PasskeyAttestationOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// Start was requested and prerequisites are being prepared.
    case preparing
    /// The attestation ceremony is in progress.
    case active(apiController: any PasskeyAttestationAPIController)
    /// The operation finished with the given result.
    case completed(result: OperationResult<AttestationResponse, PasskeyAttestationOperationFailure>)
}

/// Failure payload returned by ``PasskeyAttestationOperation``.
///
/// Every failure is terminal for the current passkey creation run. Branch on the category to decide whether to collect
/// corrected input, re-authenticate, offer another registration path, or fix provider/platform integration. Use
/// ``OperationFailure/errorCode`` as a localization key; use `apiFailure`, `underlyingError`, `challengeID`,
/// `capability`, `loginID`, and `regex` for diagnostics.
public enum PasskeyAttestationOperationFailure: OperationFailure, CustomStringConvertible {
    /// Missing, invalid, or unsupported passkey creation input.
    public enum Input: Sendable {
        /// - About: The operation could not resolve either an access token or a login ID to start passkey creation.
        /// - End-user: Ask the user to provide an identifier or restart from an authenticated state.
        /// - Developer action: Pass ``PasskeyAttestationOperationParams/loginID`` or
        ///   ``PasskeyAttestationOperationParams/accessToken``, or provide one through OwnID context.
        case missingLoginIDOrAccessToken(errorCode: ErrorCode, message: String)
        /// - About: The resolved login ID value failed validation.
        /// - End-user: Ask the user to correct the identifier.
        /// - Developer action: Keep client-side validation aligned with OwnID configuration. Use `regex` and
        ///   `apiFailure` only for diagnostics.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The resolved login ID type is not supported for passkey creation.
        /// - End-user: Ask the user for a supported identifier type, if the app lets the user choose one.
        /// - Developer action: Compare the supplied login ID type with the app's OwnID login ID configuration.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The passkey creation start request was rejected as invalid.
        /// - End-user: No direct user action unless the app can collect corrected input from the user.
        /// - Developer action: Check supplied params, resolved context values, and `apiFailure` for the rejected
        ///   operation invariant.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Account or access-token policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The user must authenticate again before passkey creation can continue.
        /// - End-user: Prompt the user to sign in again.
        /// - Developer action: Refresh credentials, verify token forwarding, and avoid retry loops without new credentials.
        case unauthorized(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The caller is not allowed to create a passkey in this context.
        /// - End-user: Explain that passkey creation is unavailable.
        /// - Developer action: Check access token claims, app policy, and operation requirements.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The account associated with the passkey creation request was not found.
        /// - End-user: Direct the user to register or sign in again, based on app state.
        /// - Developer action: Treat as an expected business outcome unless account provider data is inconsistent.
        case userNotFound(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Passkey challenge lifecycle failures.
    public enum Challenge: Sendable {
        /// - About: The active passkey creation challenge limit was reached.
        /// - End-user: Ask the user to wait briefly or finish an existing passkey creation attempt.
        /// - Developer action: Rate-limit retries and ensure abandoned challenges are canceled when possible.
        case maximumChallengesReached(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The passkey creation challenge is invalid, expired, or no longer usable.
        /// - End-user: Ask the user to restart passkey creation.
        /// - Developer action: Stop using this `challengeID`, clear local challenge state, and start a fresh operation.
        case invalid(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
        /// - About: The passkey creation challenge reached its attempt limit.
        /// - End-user: Ask the user to start passkey creation again.
        /// - Developer action: Do not retry this `challengeID`; clear local challenge state and create a new challenge.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, provider, or platform integration failures.
    public enum Integration: Sendable {
        /// - About: A backend/provider/platform dependency failed while processing passkey creation.
        /// - End-user: Show a temporary failure state or let the user try again later.
        /// - Developer action: Inspect provider configuration, iOS credential availability, `apiFailure`, and
        ///   `underlyingError`.
        case providerFailed(
            errorCode: ErrorCode,
            message: String,
            apiFailure: (any APIFailure)? = nil,
            underlyingError: (any Error & Sendable)? = nil
        )
        /// - About: A provider capability required by passkey creation is not configured.
        /// - End-user: No direct user action. The app should offer another available path.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Login ID, access token, or request input cannot be used.
    case input(Input)
    /// Account or access-token policy blocked passkey creation.
    case access(Access)
    /// Passkey creation challenge failed.
    case challenge(Challenge)
    /// SDK, app, provider, backend, or platform integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic failure state. Retrying may be reasonable after restarting passkey creation.
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
            case .unauthorized(let errorCode, let message, _),
                .forbidden(let errorCode, let message, _),
                .userNotFound(let errorCode, let message, _):
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
            case .unauthorized:
                return "Access.Unauthorized(errorCode=\(errorCode), message=\(message))"
            case .forbidden:
                return "Access.Forbidden(errorCode=\(errorCode), message=\(message))"
            case .userNotFound:
                return "Access.UserNotFound(errorCode=\(errorCode), message=\(message))"
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

/// Authenticates the user with an existing passkey.
///
/// This operation owns the full SDK-managed passkey assertion lifecycle: it starts an OwnID challenge, presents the
/// platform passkey UI through the registered ``PasskeyProtocol`` capability, verifies the platform assertion result,
/// and settles the returned ``OperationController``. Apps that want to own the platform passkey UI should use the
/// direct passkey API instead of this operation.
///
/// Explicit ``PasskeyAssertionOperationParams`` values take precedence over the current OwnID context. If
/// ``PasskeyAssertionOperationParams/accessToken`` or the context access token is available,
/// ``PasskeyAssertionOperationParams/loginID`` may be omitted. If no access token is available, the operation requires a
/// login ID from params or the current context; context login ID resolution can produce typed input or integration
/// failures.
///
/// The platform passkey prompt is owned by AuthenticationServices. The SDK supplies the current presentation context
/// through the registered passkey capability and converts the resulting passkey outcome into operation settlement:
/// successful assertion returns an ``AccessToken``, user or system cancellation returns
/// ``OperationResult/canceled(_:)``, no applicable credential returns the credential failure category, and other
/// platform or provider failures return ``OperationResult/failure(_:)``.
///
/// The returned controller represents one operation run and settles once. Keep it strongly referenced while the
/// operation is active. Calling ``OperationController/abort(reason:)`` before settlement cancels the active operation
/// with the supplied ``Reason``; when a server challenge is active, cancellation is also reported to OwnID on a
/// best-effort basis. If the challenge provides a timeout, the operation cancels with ``Reason/timeout`` after it
/// elapses. Repeated starts on the same operation object return the same controller and do not create a new passkey
/// prompt.
///
/// Requires version 16+ with passkey capabilities registered. ``OperationCapability/availability(params:)`` and
/// ``OperationCapability/isAvailable(params:)`` are preflight checks for registered dependencies and resolvable login
/// ID/access token input; ``OperationCapability/start(params:)`` revalidates the same contract and may still settle
/// with a typed failure or cancellation if runtime state changes.
public protocol PasskeyAssertionOperation: OperationCapability, Sendable
where
    Params == PasskeyAssertionOperationParams,
    Result == AccessToken,
    Failure == PasskeyAssertionOperationFailure
{}

/// Parameters for ``PasskeyAssertionOperation``.
///
/// Explicit values take precedence over the current OwnID context. A resolved access token can identify the assertion
/// request without a login ID.
public struct PasskeyAssertionOperationParams: CapabilityParams {
    /// The user's login identifier. When `nil`, the current OwnID context login ID is used if available and no access
    /// token is available. Defaults to `nil`.
    public let loginID: LoginID?
    /// An existing access token, if available. When `nil`, the current OwnID context access token is used if available.
    /// Defaults to `nil`.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    /// Creates passkey assertion parameters.
    ///
    /// - Parameters:
    ///   - loginID: User login identifier. Defaults to `nil`.
    ///   - accessToken: Existing access token, if available. Defaults to `nil`.
    public init(loginID: LoginID? = nil, accessToken: AccessToken? = nil) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.traceParent = nil
    }

    internal init(loginID: LoginID? = nil, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controller for one started ``PasskeyAssertionOperation``.
///
/// The controller settles once with ``AccessToken``, ``OperationResult/canceled(_:)``, or
/// ``PasskeyAssertionOperationFailure``.
public typealias PasskeyAssertionOperationController = any OperationController<AccessToken, PasskeyAssertionOperationFailure>

/// State value used by the passkey assertion runtime.
///
/// States progress from ``created`` through ``preparing`` and ``active(apiController:)`` to ``completed(result:)`` with
/// an ``OperationResult`` containing ``AccessToken``. The active state's direct API controller is exposed as a state
/// value for SDK UI binding; app code should settle the operation through the operation controller.
public enum PasskeyAssertionOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// Start was requested and prerequisites are being prepared.
    case preparing
    /// The assertion ceremony is in progress.
    case active(apiController: any PasskeyAssertionAPIController)
    /// The operation finished with the given result.
    case completed(result: OperationResult<AccessToken, PasskeyAssertionOperationFailure>)
}

internal enum PasskeyAssertionOperationFailureCause: Error, Sendable {
    /// Platform passkey provider failed before returning an assertion result.
    case passkeyProvider(underlyingError: (any Error & Sendable)?)
    /// Platform passkey provider reported that no matching credential is available.
    case noCredential(underlyingError: (any Error & Sendable)?)
}

/// Failure payload returned by ``PasskeyAssertionOperation``.
///
/// Every failure is terminal for the current passkey authentication run. Branch on the category to decide whether to
/// collect corrected input, offer another auth path, or fix provider/platform integration. Use
/// ``OperationFailure/errorCode`` as a localization key; use `apiFailure`, `underlyingError`, `challengeID`,
/// `capability`, `loginID`, and `regex` for diagnostics.
public enum PasskeyAssertionOperationFailure: OperationFailure, CustomStringConvertible {
    /// Missing, invalid, or unsupported passkey authentication input.
    public enum Input: Sendable {
        /// - About: The operation could not resolve either an access token or a login ID to start passkey assertion.
        /// - End-user: Ask the user to provide an identifier or restart from an authenticated state.
        /// - Developer action: Pass ``PasskeyAssertionOperationParams/loginID`` or
        ///   ``PasskeyAssertionOperationParams/accessToken``, or provide one through OwnID context.
        case missingLoginIDOrAccessToken(errorCode: ErrorCode, message: String)
        /// - About: The resolved login ID value failed validation.
        /// - End-user: Ask the user to correct the identifier.
        /// - Developer action: Keep client-side validation aligned with OwnID configuration. Use `regex` and
        ///   `apiFailure` only for diagnostics.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The resolved login ID type is not supported for passkey assertion.
        /// - End-user: Ask the user for a supported identifier type, if the app lets the user choose one.
        /// - Developer action: Compare the supplied login ID type with the app's OwnID login ID configuration.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The passkey assertion start request was rejected as invalid.
        /// - End-user: No direct user action unless the app can collect corrected input from the user.
        /// - Developer action: Check supplied params, resolved context values, and `apiFailure` for the rejected
        ///   operation invariant.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Account or access policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The account associated with the passkey assertion request was not found.
        /// - End-user: Direct the user to register or use another sign-in method, based on app state.
        /// - Developer action: Treat as an expected business outcome unless account provider data is inconsistent.
        case userNotFound(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The caller is not allowed to start or complete passkey assertion in this context.
        /// - End-user: Explain that passkey sign-in is unavailable.
        /// - Developer action: Check access token claims, app policy, and operation requirements.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Passkey challenge lifecycle failures.
    public enum Challenge: Sendable {
        /// - About: The active passkey assertion challenge limit was reached.
        /// - End-user: Ask the user to wait briefly or finish an existing sign-in attempt.
        /// - Developer action: Rate-limit retries and ensure abandoned challenges are canceled when possible.
        case maximumChallengesReached(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The passkey assertion challenge is invalid, expired, or no longer usable.
        /// - End-user: Ask the user to restart passkey sign-in.
        /// - Developer action: Stop using this `challengeID`, clear local challenge state, and start a fresh operation.
        case invalid(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
        /// - About: The passkey assertion challenge reached its attempt limit.
        /// - End-user: Ask the user to start passkey sign-in again.
        /// - Developer action: Do not retry this `challengeID`; clear local challenge state and create a new challenge.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID, apiFailure: (any APIFailure)? = nil)
    }

    /// Local credential availability failures.
    public enum Credential: Sendable {
        /// - About: No passkey was available or applicable for this assertion request.
        /// - End-user: Offer another sign-in method or ask the user to use a different account/device.
        /// - Developer action: Treat as a normal credential outcome; inspect `underlyingError` only for diagnostics.
        case noApplicablePasskeys(errorCode: ErrorCode, message: String, underlyingError: (any Error & Sendable)? = nil)
    }

    /// App, SDK, provider, or platform integration failures.
    public enum Integration: Sendable {
        /// - About: A backend/provider/platform dependency failed while processing passkey assertion.
        /// - End-user: Show a temporary failure state or let the user choose another sign-in method.
        /// - Developer action: Inspect provider configuration, iOS credential availability, `apiFailure`, and
        ///   `underlyingError`.
        case providerFailed(
            errorCode: ErrorCode,
            message: String,
            apiFailure: (any APIFailure)? = nil,
            underlyingError: (any Error & Sendable)? = nil
        )
        /// - About: A provider capability required by passkey assertion is not configured.
        /// - End-user: No direct user action. The app should offer another available sign-in method.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Login ID, access token, or request input cannot be used.
    case input(Input)
    /// Account or access policy blocked passkey assertion.
    case access(Access)
    /// Passkey assertion challenge failed.
    case challenge(Challenge)
    /// No applicable local passkey credential is available; treat separately from provider failure.
    case credential(Credential)
    /// SDK, app, provider, backend, or platform integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic failure state. Retrying may be reasonable after restarting passkey sign-in.
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
            case .userNotFound(let errorCode, let message, _), .forbidden(let errorCode, let message, _): return (errorCode, message)
            }
        case .challenge(let challenge):
            switch challenge {
            case .maximumChallengesReached(let errorCode, let message, _),
                .invalid(let errorCode, let message, _, _),
                .maximumAttemptsReached(let errorCode, let message, _, _):
                return (errorCode, message)
            }
        case .credential(let credential):
            switch credential {
            case .noApplicablePasskeys(let errorCode, let message, _): return (errorCode, message)
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
        case .credential(let credential):
            switch credential {
            case .noApplicablePasskeys:
                return "Credential.NoApplicablePasskeys(errorCode=\(errorCode), message=\(message))"
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

/// Enrolls a passkey using a proof token.
///
/// This is an API-only operation with no platform passkey UI. It does not create or retrieve local credentials; it
/// completes the OwnID enrollment boundary for a passkey that was proven by an earlier attestation or verification
/// step.
///
/// ``PasskeyEnrollOperationParams/proofToken`` is always caller-supplied.
/// ``PasskeyEnrollOperationParams/accessToken`` takes precedence over the current OwnID context access token; when
/// neither access token source is available, the operation completes with ``OperationResult/failure(_:)``. The proof
/// token and access token are used only for this enrollment run and are not a session creation mechanism.
///
/// The returned controller represents one operation run and settles once. Keep it strongly referenced while the
/// operation is active. Calling ``OperationController/abort(reason:)`` before settlement cancels the operation with the
/// supplied ``Reason``; repeated starts on the same operation object return the same controller and do not start a
/// second enrollment. On success, the passkey is enrolled and the operation completes with `Void`.
///
/// ``OperationCapability/availability(params:)`` and ``OperationCapability/isAvailable(params:)`` are preflight checks
/// for registered dependencies, ``PasskeyEnrollOperationParams/proofToken``, and a resolvable access token;
/// ``OperationCapability/start(params:)`` revalidates the same contract and may still settle with a typed failure or
/// cancellation if runtime state changes.
public protocol PasskeyEnrollOperation: OperationCapability, Sendable
where
    Params == PasskeyEnrollOperationParams,
    Result == Void,
    Failure == PasskeyEnrollOperationFailure
{}

/// Parameters for ``PasskeyEnrollOperation``.
///
/// Provide a proof token and an access token. The proof token must be supplied directly in params. When
/// ``accessToken`` is `nil`, the operation uses the current OwnID context access token when available.
public struct PasskeyEnrollOperationParams: CapabilityParams {
    /// The proof token from a prior attestation or verification step.
    public let proofToken: ProofToken
    /// An existing access token, if available. When `nil`, the current OwnID context access token is used if available.
    public let accessToken: AccessToken?
    /// Reserved for future use and currently has no observable effect. Defaults to `nil`.
    public let headless: Bool?
    internal let traceParent: String?

    /// Creates passkey enrollment parameters.
    ///
    /// - Parameters:
    ///   - proofToken: Proof token from a prior attestation or verification step.
    ///   - accessToken: Existing access token, if available.
    ///   - headless: Reserved for future use. Defaults to `nil`.
    public init(proofToken: ProofToken, accessToken: AccessToken?, headless: Bool? = nil) {
        self.proofToken = proofToken
        self.accessToken = accessToken
        self.headless = headless
        self.traceParent = nil
    }

    internal init(
        proofToken: ProofToken,
        accessToken: AccessToken?,
        headless: Bool? = nil,
        traceParent: String? = nil
    ) {
        self.proofToken = proofToken
        self.accessToken = accessToken
        self.headless = headless
        self.traceParent = traceParent
    }
}

/// Controller for one started ``PasskeyEnrollOperation``.
///
/// The controller settles once with `Void`, ``OperationResult/canceled(_:)``, or
/// ``PasskeyEnrollOperationFailure``.
public typealias PasskeyEnrollOperationController = any OperationController<Void, PasskeyEnrollOperationFailure>

/// State value used by the passkey enrollment runtime.
///
/// States progress from ``created`` through ``preparing`` to ``completed(result:)`` with an ``OperationResult``. There
/// is no active platform passkey state because enrollment is API-only.
public enum PasskeyEnrollOperationState: OperationState {
    /// Initial state before the operation starts.
    case created
    /// Start was requested and prerequisites are being prepared.
    case preparing
    /// The operation finished with the given result.
    case completed(result: OperationResult<Void, PasskeyEnrollOperationFailure>)
}

/// Failure payload returned by ``PasskeyEnrollOperation``.
///
/// Every failure is terminal for the current passkey enrollment run. Branch on the category to decide whether the app
/// must provide tokens, route to another path, or fix provider/backend integration. Use ``OperationFailure/errorCode``
/// as a localization key; use `apiFailure`, `underlyingError`, and `capability` for diagnostics.
public enum PasskeyEnrollOperationFailure: OperationFailure, CustomStringConvertible {
    /// Missing or invalid passkey enrollment input.
    public enum Input: Sendable {
        /// - About: The operation could not resolve both tokens required to enroll a passkey.
        /// - End-user: No direct user action. The app should restart the prerequisite proof or authentication step.
        /// - Developer action: Pass a proof token and provide an access token through
        ///   ``PasskeyEnrollOperationParams`` or OwnID context.
        case missingTokens(errorCode: ErrorCode, message: String)
        /// - About: The passkey enrollment request was rejected as invalid.
        /// - End-user: No direct user action unless the app can restart the prerequisite step.
        /// - Developer action: Check proof-token/access-token pairing and `apiFailure` for the rejected operation
        ///   invariant.
        case invalidRequest(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Account or access-token policy failures returned by OwnID.
    public enum Access: Sendable {
        /// - About: The account referenced by the enrollment tokens was not found.
        /// - End-user: Direct the user to register or sign in again, based on app state.
        /// - Developer action: Treat as an expected business outcome unless token/account data is inconsistent.
        case userNotFound(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: The caller is not allowed to enroll a passkey for this account/context.
        /// - End-user: Explain that passkey enrollment is unavailable.
        /// - Developer action: Check access token claims, proof-token origin, and app policy.
        case forbidden(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
    }

    /// App, SDK, provider, or backend integration failures.
    public enum Integration: Sendable {
        /// - About: A configured backend/provider dependency failed while enrolling the passkey.
        /// - End-user: Show a temporary failure state.
        /// - Developer action: Log provider context and monitor the integration before retrying aggressively.
        case providerFailed(errorCode: ErrorCode, message: String, apiFailure: (any APIFailure)? = nil)
        /// - About: A provider capability required by passkey enrollment is not configured.
        /// - End-user: No direct user action. The app should offer another available path.
        /// - Developer action: Configure the missing `capability` for the app and deployment environment.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, apiFailure: (any APIFailure)? = nil)
    }

    /// Access token, proof token, or request input cannot be used.
    case input(Input)
    /// Account or access-token policy blocked passkey enrollment.
    case access(Access)
    /// SDK, app, backend, or provider integration failed.
    case integration(Integration)
    /// - About: The operation stopped because of an unexpected SDK/runtime failure or an internal invariant violation.
    /// - End-user: Show a generic failure state. Retrying may be reasonable after restarting the enrollment step.
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
            case .missingTokens(let errorCode, let message),
                .invalidRequest(let errorCode, let message, _):
                return (errorCode, message)
            }
        case .access(let access):
            switch access {
            case .userNotFound(let errorCode, let message, _), .forbidden(let errorCode, let message, _): return (errorCode, message)
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
            case .missingTokens:
                return "Input.MissingTokens(errorCode=\(errorCode), message=\(message))"
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
