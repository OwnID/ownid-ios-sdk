import Foundation

/// Starts passkey creation and returns an attestation challenge controller.
///
/// This is the direct API surface for apps that own their platform passkey UI. ``start(params:)`` asks OwnID for
/// WebAuthn ``AttestationOptions``, validates the server-provided WebAuthn fields that the SDK must decode, and returns
/// a controller tied to that challenge. The SDK does not call AuthenticationServices from this API and does not check
/// device passkey availability; pass ``PasskeyAttestationAPIController/attestationOptions`` to your platform passkey
/// layer, then pass the resulting ``AttestationResult`` to
/// ``PasskeyAttestationAPIController/verify(attestationResult:)``.
///
/// The controller owns the challenge returned by ``start(params:)``. Verification completes the challenge and returns
/// an ``AttestationResponse`` containing OwnID data and a proof token for the app's registration boundary. Cancellation
/// reports that the challenge was abandoned; it is best-effort and may fail if the challenge already expired, was
/// completed, or was canceled.
///
/// If the Swift task running ``start(params:)``, `verify`, or `cancel` is canceled first, the API returns
/// ``APIResult/canceled``.
///
/// OpenAPI source: `attestationOptions` operation.
public protocol PasskeyAttestationAPI: APICapability {
    /// Starts the passkey attestation flow.
    ///
    /// The SDK resolves optional values from `params` first, then from the current ``Context``. On success, the returned
    /// controller captures the resolved access token and challenge; subsequent context changes do not affect it.
    ///
    /// - Parameter params: Optional attestation parameters. When omitted, the API uses values from the current
    ///   ``Context`` where available.
    /// - Returns: ``APIResult/success(_:)`` with the challenge controller, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `attestationOptions` operation; `AttestationOptionsResponse` success response schema.
    func start(
        params: PasskeyAttestationAPIParams?
    ) async -> APIResult<any PasskeyAttestationAPIController, PasskeyAttestationStartAPIFailure>
}

/// Parameters for the passkey attestation API request.
///
/// - Parameters:
///   - loginID: The user's login identifier to register the passkey for. When `nil`, the login ID from the current
///     ``Context`` is used if available. Raw context login IDs are resolved through the configured login ID validator;
///     resolution failures are returned as typed start failures. It may be omitted when an access token is supplied or
///     available from the current ``Context``. Defaults to `nil`.
///   - accountDisplayName: A human-readable name for the account, shown in platform passkey UI. When `nil`, the
///     account display name from the current ``Context`` is used if available. Defaults to `nil`.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. The token resolved by ``PasskeyAttestationAPI/start(params:)`` is
///     reused by the returned controller's verification call; later ``Context`` changes do not update an existing
///     controller. Defaults to `nil`.
///
/// OpenAPI source: `AttestationOptionsRequest` schema.
public struct PasskeyAttestationAPIParams: Sendable {
    /// User login identifier to register the passkey for.
    public let loginID: LoginID?
    /// Account display name shown by the platform credential manager when available.
    public let accountDisplayName: String?
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    public init(loginID: LoginID? = nil, accountDisplayName: String? = nil, accessToken: AccessToken? = nil) {
        self.init(loginID: loginID, accountDisplayName: accountDisplayName, accessToken: accessToken, traceParent: nil)
    }

    internal init(loginID: LoginID? = nil, accountDisplayName: String? = nil, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.loginID = loginID
        self.accountDisplayName = accountDisplayName
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controls an active passkey attestation challenge.
///
/// ``attestationOptions`` contains relying party info, user info, challenge, supported algorithms, attestation
/// preference, authenticator selection criteria, and timeout. Call
/// ``verify(attestationResult:)`` with the platform credential result for this challenge to complete registration and
/// receive an ``AttestationResponse``. Call ``cancel(reason:)`` when the app abandons the challenge before verification.
///
/// Keep the controller strongly referenced while the challenge can still verify or cancel. Releasing the controller
/// does not cancel the challenge automatically.
///
/// OpenAPI source: `AttestationOptionsResponse` success response schema, with linked `attestationResult` and
/// `attestationCancel` operations.
public protocol PasskeyAttestationAPIController: Sendable {
    /// WebAuthn attestation options to pass to the platform credential manager.
    ///
    /// OpenAPI source: `AttestationOptionsResponse` schema.
    var attestationOptions: AttestationOptions { get }

    /// Verifies the attestation result from the platform passkey provider.
    ///
    /// The result must correspond to this controller's ``attestationOptions``. A stale, expired, already-completed, or
    /// mismatched challenge is returned as
    /// ``PasskeyAttestationVerifyAPIFailure/BadRequest/invalidChallenge(errorCode:message:challengeID:)`` when the
    /// backend can classify it.
    ///
    /// - Parameter attestationResult: The platform passkey result for this challenge.
    /// - Returns: ``APIResult/success(_:)`` with the verified attestation response, ``APIResult/failure(_:)`` with a
    ///   typed failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `attestationResult` operation; `AttestationResultRequest` request schema.
    func verify(attestationResult: AttestationResult) async -> APIResult<AttestationResponse, PasskeyAttestationVerifyAPIFailure>

    /// Cancels the attestation flow.
    ///
    /// A successful result means OwnID accepted the cancellation. If the challenge is already terminal or unknown, the
    /// backend may return a typed bad-request failure.
    ///
    /// - Parameter reason: The caller-visible reason for canceling the challenge.
    /// - Returns: ``APIResult/success(_:)`` when the cancel request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `attestationCancel` operation.
    func cancel(reason: Reason) async -> APIResult<Void, PasskeyAttestationCancelAPIFailure>
}

/// Native failure hierarchy returned by ``PasskeyAttestationAPI/start(params:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `attestationOptions` operation, plus
/// ``PasskeyAttestationStartAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `attestationOptions` operation.
public enum PasskeyAttestationStartAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request.
    ///
    /// OpenAPI source: `BadLoginIdRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
        /// About: The login ID value does not match the validation rule configured for its type.
        ///
        /// End-user: Ask the user to correct the identifier.
        ///
        /// Developer action: Surface the configured regex only in diagnostics and keep client validation aligned with server config.
        ///
        /// - Parameters:
        ///   - loginID: Login ID value that failed validation.
        ///   - regex: Validation regex configured for the login ID type.
        ///
        /// OpenAPI source: `LoginIdValidationError` schema.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String)
        /// About: The supplied login ID type is not supported by the app or operation.
        ///
        /// End-user: Ask for a supported identifier such as email or phone, based on app configuration.
        ///
        /// Developer action: Compare the requested login ID type with the app's login ID configuration.
        ///
        /// OpenAPI source: `LoginIdTypeNotSupportedError` schema.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Provider or capability dependency failed.
    ///
    /// OpenAPI source: `FailedDependencyErrorResponse` response component.
    public enum FailedDependency: Sendable {
        /// About: A configured provider failed while OwnID was processing the operation, e.g. integration-endpoint failed
        /// to fetch the user, email-server failed to send the email.
        ///
        /// End-user: Show a temporary failure message.
        ///
        /// Developer action: Log provider request context, monitor the provider integration, and escalate repeated failures.
        ///
        /// - Parameter scope: Provider or capability scope associated with the dependency failure.
        ///
        /// OpenAPI source: `ProviderError` schema.
        case providerFailed(errorCode: ErrorCode, message: String, scope: APIFailureScope)
        /// About: No provider is configured for the capability required by the operation, e.g. send SMS for
        /// phone-verification.
        ///
        /// End-user: Not Applicable.
        ///
        /// Developer action: Configure the missing provider capability for the app and deployment environment.
        ///
        /// - Parameters:
        ///   - capability: Missing provider capability required by the operation.
        ///   - scope: Provider or capability scope associated with the missing capability.
        ///
        /// OpenAPI source: `MissingProviderError` schema.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, scope: APIFailureScope)
    }

    /// Bad request.
    ///
    /// OpenAPI source: `BadLoginIdRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// About: The caller is authenticated but not allowed to perform the operation.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check access token claims or the operation's policy for the required claims.
    ///
    /// OpenAPI source: `ForbiddenError` schema.
    case forbidden(errorCode: ErrorCode, message: String)
    /// Provider or capability dependency failed.
    ///
    /// OpenAPI source: `FailedDependencyErrorResponse` response component.
    case failedDependency(FailedDependency)
    /// About: The active challenge limit or concurrency guard was reached.
    ///
    /// End-user: Ask the user to wait briefly or finish an existing challenge before starting another.
    ///
    /// Developer action: Rate-limit retries, log repeated occurrences, and inspect challenge cleanup if this persists.
    ///
    /// OpenAPI source: `MaximumChallengesReachedError` schema.
    case maximumChallengesReached(errorCode: ErrorCode, message: String)
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error,
    /// unhandled HTTP status, or response mapping failure.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for transport, status handling, or
    /// response mapping issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)),
            .badRequest(.invalidLoginID(let errorCode, _, _, _)),
            .badRequest(.unsupportedLoginIDType(let errorCode, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .maximumChallengesReached(let errorCode, _): return errorCode
        case .forbidden(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidLoginID(_, let message, _, _)),
            .badRequest(.unsupportedLoginIDType(_, let message)),
            .badRequest(.unknown(_, let message)):
            return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
            return message
        case .maximumChallengesReached(_, let message): return message
        case .forbidden(_, let message), .unexpected(_, let message, _): return message
        }
    }

    public var description: String {
        switch self {
        case .badRequest(.invalidArgument):
            return "BadRequest.InvalidArgument(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.invalidLoginID):
            return "BadRequest.InvalidLoginID(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unsupportedLoginIDType):
            return "BadRequest.UnsupportedLoginIDType(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .maximumChallengesReached:
            return "MaximumChallengesReached(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``PasskeyAttestationAPIController/verify(attestationResult:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `attestationResult` operation, plus
/// ``PasskeyAttestationVerifyAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `attestationResult` operation.
public enum PasskeyAttestationVerifyAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
        /// About: The challenge was not found, expired or already completed.
        ///
        /// End-user: Ask the user to restart the operation.
        ///
        /// Developer action: Stop polling or completing this challenge ID and create a fresh challenge.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `InvalidChallengeError` schema.
        case invalidChallenge(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The user exhausted the allowed verification attempts for the challenge.
        ///
        /// End-user: Ask the user to start a new challenge.
        ///
        /// Developer action: Do not retry the same challenge; clear local challenge state and restart the flow.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `MaximumAttemptsReachedError` schema.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// About: The caller is missing valid authentication for the operation.
    ///
    /// End-user: Prompt the user to authenticate again.
    ///
    /// Developer action: Refresh credentials, verify token forwarding, and avoid retry loops without new credentials.
    ///
    /// OpenAPI source: `UnauthorizedError` schema.
    case unauthorized(errorCode: ErrorCode, message: String)
    /// About: The caller is authenticated but not allowed to perform the operation.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check access token claims or the operation's policy for the required claims.
    ///
    /// OpenAPI source: `ForbiddenError` schema.
    case forbidden(errorCode: ErrorCode, message: String)
    /// About: The account provider did not find an account for the requested login ID.
    ///
    /// End-user: Direct the user to register an account.
    ///
    /// Developer action: Treat this as an expected business outcome; do not escalate unless provider data is inconsistent.
    ///
    /// OpenAPI source: `UserNotFoundError` schema.
    case userNotFound(errorCode: ErrorCode, message: String)
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error,
    /// unhandled HTTP status, or response mapping failure.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for transport, status handling, or
    /// response mapping issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)),
            .badRequest(.invalidChallenge(let errorCode, _, _)),
            .badRequest(.maximumAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .unauthorized(let errorCode, _), .forbidden(let errorCode, _), .userNotFound(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidChallenge(_, let message, _)),
            .badRequest(.maximumAttemptsReached(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .unauthorized(_, let message), .forbidden(_, let message), .userNotFound(_, let message), .unexpected(_, let message, _):
            return message
        }
    }

    public var description: String {
        switch self {
        case .badRequest(.invalidArgument):
            return "BadRequest.InvalidArgument(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.invalidChallenge):
            return "BadRequest.InvalidChallenge(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.maximumAttemptsReached):
            return "BadRequest.MaximumAttemptsReached(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .unauthorized:
            return "Unauthorized(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .userNotFound:
            return "UserNotFound(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``PasskeyAttestationAPIController/cancel(reason:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `attestationCancel` operation, plus
/// ``PasskeyAttestationCancelAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `attestationCancel` operation.
public enum PasskeyAttestationCancelAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
        /// About: The challenge was not found, expired or already completed.
        ///
        /// End-user: Ask the user to restart the operation.
        ///
        /// Developer action: Stop polling or completing this challenge ID and create a fresh challenge.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `InvalidChallengeError` schema.
        case invalidChallenge(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The user exhausted the allowed verification attempts for the challenge.
        ///
        /// End-user: Ask the user to start a new challenge.
        ///
        /// Developer action: Do not retry the same challenge; clear local challenge state and restart the flow.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `MaximumAttemptsReachedError` schema.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error,
    /// unhandled HTTP status, or response mapping failure.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for transport, status handling, or
    /// response mapping issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)),
            .badRequest(.invalidChallenge(let errorCode, _, _)),
            .badRequest(.maximumAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidChallenge(_, let message, _)),
            .badRequest(.maximumAttemptsReached(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .unexpected(_, let message, _): return message
        }
    }

    public var description: String {
        switch self {
        case .badRequest(.invalidArgument):
            return "BadRequest.InvalidArgument(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.invalidChallenge):
            return "BadRequest.InvalidChallenge(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.maximumAttemptsReached):
            return "BadRequest.MaximumAttemptsReached(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Starts passkey authentication and returns an assertion challenge controller.
///
/// This is the direct API surface for apps that own their platform passkey UI. ``start(params:)`` asks OwnID for
/// WebAuthn ``AssertionOptions``, validates the server-provided WebAuthn fields that the SDK must decode, and returns a
/// controller tied to that challenge. The SDK does not call AuthenticationServices from this API and does not check
/// device passkey availability; pass ``PasskeyAssertionAPIController/assertionOptions`` to your platform passkey layer,
/// then pass the resulting ``AssertionResult`` to ``PasskeyAssertionAPIController/verify(assertionResult:)``.
///
/// The controller owns the challenge returned by ``start(params:)``. Verification completes the challenge and returns
/// an ``AccessToken``. Cancellation reports that the challenge was abandoned; it is best-effort and may fail if the
/// challenge already expired, was completed, or was canceled.
///
/// If the Swift task running ``start(params:)``, `verify`, or `cancel` is canceled first, the API returns
/// ``APIResult/canceled``.
///
/// OpenAPI source: `assertionOptions` operation.
public protocol PasskeyAssertionAPI: APICapability {
    /// Starts the passkey assertion flow.
    ///
    /// The SDK resolves optional values from `params` first, then from the current ``Context``. On success, the returned
    /// controller captures the resolved access token and challenge; subsequent context changes do not affect it.
    ///
    /// - Parameter params: Optional assertion parameters. When omitted, the API uses values from the current
    ///   ``Context`` where available.
    /// - Returns: ``APIResult/success(_:)`` with the challenge controller, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `assertionOptions` operation; `AssertionOptionsResponse` success response schema.
    func start(params: PasskeyAssertionAPIParams?) async -> APIResult<any PasskeyAssertionAPIController, PasskeyAssertionStartAPIFailure>
}

/// Parameters for the passkey assertion API request.
///
/// - Parameters:
///   - loginID: The user's login identifier. When `nil`, the login ID from the current ``Context`` is used if
///     available. Raw context login IDs are resolved through the configured login ID validator; resolution failures are
///     returned as typed start failures. It may be omitted when an access token is supplied or available from the
///     current ``Context``. Defaults to `nil`.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. The token resolved by ``PasskeyAssertionAPI/start(params:)`` is
///     reused by the returned controller's verification call; later ``Context`` changes do not update an existing
///     controller. Defaults to `nil`.
///
/// OpenAPI source: `AssertionOptionsRequest` schema.
public struct PasskeyAssertionAPIParams: Sendable {
    /// User login identifier for the assertion challenge.
    public let loginID: LoginID?
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    public init(loginID: LoginID? = nil, accessToken: AccessToken? = nil) {
        self.init(loginID: loginID, accessToken: accessToken, traceParent: nil)
    }

    internal init(loginID: LoginID? = nil, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controls an active passkey assertion challenge.
///
/// ``assertionOptions`` contains the challenge, relying party ID, allowed credentials, user verification preference,
/// and timeout. Call ``verify(assertionResult:)`` with the platform credential result for this challenge to complete
/// authentication and receive an ``AccessToken``. Call ``cancel(reason:)`` when the app abandons the challenge before
/// verification.
///
/// Keep the controller strongly referenced while the challenge can still verify or cancel. Releasing the controller
/// does not cancel the challenge automatically.
///
/// OpenAPI source: `AssertionOptionsResponse` success response schema, with linked `assertionResult` and
/// `assertionCancel` operations.
public protocol PasskeyAssertionAPIController: Sendable {
    /// WebAuthn assertion options to pass to the platform credential manager.
    ///
    /// OpenAPI source: `AssertionOptionsResponse` schema.
    var assertionOptions: AssertionOptions { get }

    /// Verifies the assertion result from the platform passkey provider.
    ///
    /// The result must correspond to this controller's ``assertionOptions``. A stale, expired, already-completed, or
    /// mismatched challenge is returned as
    /// ``PasskeyAssertionVerifyAPIFailure/BadRequest/invalidChallenge(errorCode:message:challengeID:)`` when the backend
    /// can classify it.
    ///
    /// - Parameter assertionResult: The platform passkey result for this challenge.
    /// - Returns: ``APIResult/success(_:)`` with the access token, ``APIResult/failure(_:)`` with a typed failure, or
    ///   ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `assertionResult` operation; `AssertionResultRequest` request schema.
    func verify(assertionResult: AssertionResult) async -> APIResult<AccessToken, PasskeyAssertionVerifyAPIFailure>

    /// Cancels the assertion flow.
    ///
    /// A successful result means OwnID accepted the cancellation. If the challenge is already terminal or unknown, the
    /// backend may return a typed bad-request failure.
    ///
    /// - Parameter reason: The caller-visible reason for canceling the challenge.
    /// - Returns: ``APIResult/success(_:)`` when the cancel request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `assertionCancel` operation.
    func cancel(reason: Reason) async -> APIResult<Void, PasskeyAssertionCancelAPIFailure>
}

/// Native failure hierarchy returned by ``PasskeyAssertionAPI/start(params:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `assertionOptions` operation, plus
/// ``PasskeyAssertionStartAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `assertionOptions` operation.
public enum PasskeyAssertionStartAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request.
    ///
    /// OpenAPI source: `BadLoginIdRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
        /// About: The login ID value does not match the validation rule configured for its type.
        ///
        /// End-user: Ask the user to correct the identifier.
        ///
        /// Developer action: Surface the configured regex only in diagnostics and keep client validation aligned with server config.
        ///
        /// - Parameters:
        ///   - loginID: Login ID value that failed validation.
        ///   - regex: Validation regex configured for the login ID type.
        ///
        /// OpenAPI source: `LoginIdValidationError` schema.
        case invalidLoginID(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String)
        /// About: The supplied login ID type is not supported by the app or operation.
        ///
        /// End-user: Ask for a supported identifier such as email or phone, based on app configuration.
        ///
        /// Developer action: Compare the requested login ID type with the app's login ID configuration.
        ///
        /// OpenAPI source: `LoginIdTypeNotSupportedError` schema.
        case unsupportedLoginIDType(errorCode: ErrorCode, message: String)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Provider or capability dependency failed.
    ///
    /// OpenAPI source: `FailedDependencyErrorResponse` response component.
    public enum FailedDependency: Sendable {
        /// About: A configured provider failed while OwnID was processing the operation, e.g. integration-endpoint failed
        /// to fetch the user, email-server failed to send the email.
        ///
        /// End-user: Show a temporary failure message.
        ///
        /// Developer action: Log provider request context, monitor the provider integration, and escalate repeated failures.
        ///
        /// - Parameter scope: Provider or capability scope associated with the dependency failure.
        ///
        /// OpenAPI source: `ProviderError` schema.
        case providerFailed(errorCode: ErrorCode, message: String, scope: APIFailureScope)
        /// About: No provider is configured for the capability required by the operation, e.g. send SMS for
        /// phone-verification.
        ///
        /// End-user: Not Applicable.
        ///
        /// Developer action: Configure the missing provider capability for the app and deployment environment.
        ///
        /// - Parameters:
        ///   - capability: Missing provider capability required by the operation.
        ///   - scope: Provider or capability scope associated with the missing capability.
        ///
        /// OpenAPI source: `MissingProviderError` schema.
        case missingProvider(errorCode: ErrorCode, message: String, capability: String, scope: APIFailureScope)
    }

    /// Bad request.
    ///
    /// OpenAPI source: `BadLoginIdRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// About: The caller is authenticated but not allowed to perform the operation.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check access token claims or the operation's policy for the required claims.
    ///
    /// OpenAPI source: `ForbiddenError` schema.
    case forbidden(errorCode: ErrorCode, message: String)
    /// About: The account provider did not find an account for the requested login ID.
    ///
    /// End-user: Direct the user to register an account.
    ///
    /// Developer action: Treat this as an expected business outcome; do not escalate unless provider data is inconsistent.
    ///
    /// OpenAPI source: `UserNotFoundError` schema.
    case userNotFound(errorCode: ErrorCode, message: String)
    /// Provider or capability dependency failed.
    ///
    /// OpenAPI source: `FailedDependencyErrorResponse` response component.
    case failedDependency(FailedDependency)
    /// About: The active challenge limit or concurrency guard was reached.
    ///
    /// End-user: Ask the user to wait briefly or finish an existing challenge before starting another.
    ///
    /// Developer action: Rate-limit retries, log repeated occurrences, and inspect challenge cleanup if this persists.
    ///
    /// OpenAPI source: `MaximumChallengesReachedError` schema.
    case maximumChallengesReached(errorCode: ErrorCode, message: String)
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error,
    /// unhandled HTTP status, or response mapping failure.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for transport, status handling, or
    /// response mapping issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)),
            .badRequest(.invalidLoginID(let errorCode, _, _, _)),
            .badRequest(.unsupportedLoginIDType(let errorCode, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .maximumChallengesReached(let errorCode, _): return errorCode
        case .forbidden(let errorCode, _), .userNotFound(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidLoginID(_, let message, _, _)),
            .badRequest(.unsupportedLoginIDType(_, let message)),
            .badRequest(.unknown(_, let message)):
            return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
            return message
        case .maximumChallengesReached(_, let message): return message
        case .forbidden(_, let message), .userNotFound(_, let message), .unexpected(_, let message, _): return message
        }
    }

    public var description: String {
        switch self {
        case .badRequest(.invalidArgument):
            return "BadRequest.InvalidArgument(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.invalidLoginID):
            return "BadRequest.InvalidLoginID(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unsupportedLoginIDType):
            return "BadRequest.UnsupportedLoginIDType(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .userNotFound:
            return "UserNotFound(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .maximumChallengesReached:
            return "MaximumChallengesReached(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``PasskeyAssertionAPIController/verify(assertionResult:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `assertionResult` operation, plus
/// ``PasskeyAssertionVerifyAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `assertionResult` operation.
public enum PasskeyAssertionVerifyAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
        /// About: The challenge was not found, expired or already completed.
        ///
        /// End-user: Ask the user to restart the operation.
        ///
        /// Developer action: Stop polling or completing this challenge ID and create a fresh challenge.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `InvalidChallengeError` schema.
        case invalidChallenge(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The user exhausted the allowed verification attempts for the challenge.
        ///
        /// End-user: Ask the user to start a new challenge.
        ///
        /// Developer action: Do not retry the same challenge; clear local challenge state and restart the flow.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `MaximumAttemptsReachedError` schema.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// About: The caller is authenticated but not allowed to perform the operation.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check access token claims or the operation's policy for the required claims.
    ///
    /// OpenAPI source: `ForbiddenError` schema.
    case forbidden(errorCode: ErrorCode, message: String)
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error,
    /// unhandled HTTP status, or response mapping failure.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for transport, status handling, or
    /// response mapping issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)),
            .badRequest(.invalidChallenge(let errorCode, _, _)),
            .badRequest(.maximumAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .forbidden(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidChallenge(_, let message, _)),
            .badRequest(.maximumAttemptsReached(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .forbidden(_, let message), .unexpected(_, let message, _):
            return message
        }
    }

    public var description: String {
        switch self {
        case .badRequest(.invalidArgument):
            return "BadRequest.InvalidArgument(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.invalidChallenge):
            return "BadRequest.InvalidChallenge(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.maximumAttemptsReached):
            return "BadRequest.MaximumAttemptsReached(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``PasskeyAssertionAPIController/cancel(reason:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `assertionCancel` operation, plus
/// ``PasskeyAssertionCancelAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `assertionCancel` operation.
public enum PasskeyAssertionCancelAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
        /// About: The challenge was not found, expired or already completed.
        ///
        /// End-user: Ask the user to restart the operation.
        ///
        /// Developer action: Stop polling or completing this challenge ID and create a fresh challenge.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `InvalidChallengeError` schema.
        case invalidChallenge(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The user exhausted the allowed verification attempts for the challenge.
        ///
        /// End-user: Ask the user to start a new challenge.
        ///
        /// Developer action: Do not retry the same challenge; clear local challenge state and restart the flow.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `MaximumAttemptsReachedError` schema.
        case maximumAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Bad request against an existing challenge.
    ///
    /// OpenAPI source: `BadChallengeRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error,
    /// unhandled HTTP status, or response mapping failure.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for transport, status handling, or
    /// response mapping issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)),
            .badRequest(.invalidChallenge(let errorCode, _, _)),
            .badRequest(.maximumAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidChallenge(_, let message, _)),
            .badRequest(.maximumAttemptsReached(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .unexpected(_, let message, _): return message
        }
    }

    public var description: String {
        switch self {
        case .badRequest(.invalidArgument):
            return "BadRequest.InvalidArgument(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.invalidChallenge):
            return "BadRequest.InvalidChallenge(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.maximumAttemptsReached):
            return "BadRequest.MaximumAttemptsReached(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
