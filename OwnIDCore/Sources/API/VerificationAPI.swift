import Foundation

/// Starts an email verification challenge and returns a challenge controller.
///
/// The returned controller owns the challenge and exposes linked complete, resend, and cancel calls so the app does
/// not pass the challenge ID manually.
/// Linked calls use the challenge returned by ``start(params:)`` and the access token supplied to ``start(params:)``,
/// or the access token available from the current ``Context``.
///
/// OpenAPI source: `startEmailVerification` operation.
public protocol EmailVerificationAPI: APICapability {
    /// Starts the email verification flow.
    ///
    /// - Parameter params: Optional verification parameters. When omitted, the API uses values from the current
    ///   ``Context`` where available.
    /// - Returns: ``APIResult/success(_:)`` with the challenge controller, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `startEmailVerification` operation; `StartVerificationResponse` success response schema.
    func start(params: EmailVerificationAPIParams?) async -> APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure>
}

/// Parameters for the email verification API request.
///
/// - Parameters:
///   - loginID: The email address to verify. When `nil`, the login ID from the current ``Context`` is used if
///     available. It may be omitted when an access token is supplied or available from the current ``Context``. If the
///     current ``Context`` contains a raw login ID, it must resolve to a supported typed login ID or
///     ``EmailVerificationAPI/start(params:)`` returns a typed failure.
///     Defaults to `nil`.
///   - loginIDHintID: An optional hint identifier for the login ID. Defaults to `nil`.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. The same token is used by the controller's linked calls. Defaults
///     to `nil`.
///   - verificationMethods: Preferred verification methods (OTP, magic link). When `nil`, the server chooses available
///     methods. Defaults to `nil`.
///   - magicLinkRedirectURL: An optional URL to which the user will be redirected after clicking a magic link, if that
///     verification method is requested and used. Defaults to `nil`.
///
/// OpenAPI source: `StartVerificationRequest` schema.
public struct EmailVerificationAPIParams: Sendable {
    /// Email address to verify.
    public let loginID: LoginID?
    /// Optional hint identifier for the login ID.
    public let loginIDHintID: String?
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    /// Preferred verification methods.
    public let verificationMethods: Set<VerificationMethod>?
    /// Redirect URL used if the selected verification method needs a magic-link redirect.
    public let magicLinkRedirectURL: String?
    internal let traceParent: String?

    public init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        verificationMethods: Set<VerificationMethod>? = nil,
        magicLinkRedirectURL: String? = nil
    ) {
        self.init(
            loginID: loginID,
            loginIDHintID: loginIDHintID,
            accessToken: accessToken,
            verificationMethods: verificationMethods,
            magicLinkRedirectURL: magicLinkRedirectURL,
            traceParent: nil
        )
    }

    internal init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        verificationMethods: Set<VerificationMethod>? = nil,
        magicLinkRedirectURL: String? = nil,
        traceParent: String? = nil
    ) {
        self.loginID = loginID
        self.loginIDHintID = loginIDHintID
        self.accessToken = accessToken
        self.verificationMethods = verificationMethods
        self.magicLinkRedirectURL = magicLinkRedirectURL
        self.traceParent = traceParent
    }
}

/// Controls an active email verification challenge.
///
/// ``challenge`` includes the available methods, attempt limits, resend policy, and timeout. The SDK does not enforce
/// attempt, resend, or timeout limits locally; the server response for each linked call is returned as that call's
/// typed ``APIResult``.
///
/// Keep the controller strongly referenced while the challenge can still complete, resend, or cancel. Releasing the
/// controller does not cancel the challenge automatically.
///
/// OpenAPI source: `StartVerificationResponse` success response schema, with linked `completeEmailVerification`,
/// `resendEmailVerification`, and `cancelEmailVerification` operations.
public protocol EmailVerificationAPIController: Sendable {
    /// The verification challenge with details such as supported methods and resend policy.
    ///
    /// OpenAPI source: `StartVerificationResponse` schema.
    var challenge: VerificationChallenge { get }

    /// Submits a verification code.
    ///
    /// - Parameter code: The verification code entered by the user.
    /// - Returns: ``APIResult/success(_:)`` with the token produced by verification, which can be an access token or a
    ///   proof token, ``APIResult/failure(_:)`` with a typed failure such as an invalid, expired, exhausted, or
    ///   wrong-code challenge, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `completeEmailVerification` operation; `CompleteVerificationRequest` request schema.
    func completeWithCode(code: String) async -> APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>

    /// Requests a new verification code to be sent.
    ///
    /// - Returns: ``APIResult/success(_:)`` when the resend request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure for server-enforced resend limits, debounce, or provider failures, or ``APIResult/canceled`` if the
    ///   surrounding task is canceled first.
    ///
    /// OpenAPI source: `resendEmailVerification` operation.
    func resend() async -> APIResult<Void, EmailVerificationResendAPIFailure>

    /// Cancels the verification flow.
    ///
    /// - Parameter reason: The caller-visible reason for canceling the challenge.
    /// - Returns: ``APIResult/success(_:)`` when the cancel request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first. Canceling the Swift task does
    ///   not cancel the server-side challenge; call this method when the app wants to request challenge cancellation.
    ///
    /// OpenAPI source: `cancelEmailVerification` operation.
    func cancel(reason: Reason) async -> APIResult<Void, EmailVerificationCancelAPIFailure>
}

/// Native failure hierarchy returned by ``EmailVerificationAPI/start(params:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `startEmailVerification` operation, plus
/// ``EmailVerificationStartAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `startEmailVerification` operation.
public enum EmailVerificationStartAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad verification start request.
    ///
    /// OpenAPI source: `BadVerificationRequestErrorResponse` response component.
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
        /// About: The selected verification channel is unavailable for the login ID.
        ///
        /// End-user: Offer another authentication method or ask the user to update account contact details.
        ///
        /// Developer action: Check account provider data and channel configuration before retrying.
        ///
        /// - Parameter loginID: Login ID for which the selected verification channel is unavailable.
        ///
        /// OpenAPI source: `MissingChannelError` schema.
        case missingChannel(errorCode: ErrorCode, message: String, loginID: LoginID)
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

    /// Bad verification start request.
    ///
    /// OpenAPI source: `BadVerificationRequestErrorResponse` response component.
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
            .badRequest(.missingChannel(let errorCode, _, _)),
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
            .badRequest(.missingChannel(_, let message, _)),
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
        case .badRequest(.missingChannel):
            return "BadRequest.MissingChannel(errorCode=\(errorCode), message=\(message))"
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

/// Native failure hierarchy returned by ``EmailVerificationAPIController/completeWithCode(code:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `completeEmailVerification` operation, plus
/// ``EmailVerificationCompleteAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `completeEmailVerification` operation.
public enum EmailVerificationCompleteAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while completing a verification challenge.
    ///
    /// OpenAPI source: `BadCompleteVerificationRequestErrorResponse` response component.
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
        /// About: The submitted verification code or equivalent challenge proof is incorrect.
        ///
        /// End-user: Ask the user to try again while attempts remain.
        ///
        /// Developer action: Keep the current challenge active and update remaining-attempt UI if available.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `VerificationCodeWrongError` schema.
        case wrongCode(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Bad request while completing a verification challenge.
    ///
    /// OpenAPI source: `BadCompleteVerificationRequestErrorResponse` response component.
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
            .badRequest(.wrongCode(let errorCode, _, _)),
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
            .badRequest(.wrongCode(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .forbidden(_, let message), .unexpected(_, let message, _): return message
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
        case .badRequest(.wrongCode):
            return "BadRequest.WrongCode(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``EmailVerificationAPIController/resend()``.
///
/// Direct cases correspond to OpenAPI error response components for the `resendEmailVerification` operation, plus
/// ``EmailVerificationResendAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `resendEmailVerification` operation.
public enum EmailVerificationResendAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while resending a verification challenge code.
    ///
    /// OpenAPI source: `BadResendRequestErrorResponse` response component.
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
        /// About: The verification code resend limit or debounce policy was reached.
        ///
        /// End-user: Ask the user to wait or restart the challenge.
        ///
        /// Developer action: Disable resend UI for the current challenge and respect the server resend policy.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `MaximumResendAttemptsReachedError` schema.
        case maximumResendAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
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

    /// Bad request while resending a verification challenge code.
    ///
    /// OpenAPI source: `BadResendRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// Provider or capability dependency failed.
    ///
    /// OpenAPI source: `FailedDependencyErrorResponse` response component.
    case failedDependency(FailedDependency)
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
            .badRequest(.maximumResendAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidChallenge(_, let message, _)),
            .badRequest(.maximumResendAttemptsReached(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
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
        case .badRequest(.maximumResendAttemptsReached):
            return "BadRequest.MaximumResendAttemptsReached(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``EmailVerificationAPIController/cancel(reason:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `cancelEmailVerification` operation, plus
/// ``EmailVerificationCancelAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `cancelEmailVerification` operation.
public enum EmailVerificationCancelAPIFailure: APIFailure, CustomStringConvertible {
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

/// Starts a phone number verification challenge and returns a challenge controller.
///
/// The returned controller owns the challenge and exposes linked complete, resend, and cancel calls so the app does
/// not pass the challenge ID manually.
/// Linked calls use the challenge returned by ``start(params:)`` and the access token supplied to ``start(params:)``,
/// or the access token available from the current ``Context``.
///
/// OpenAPI source: `startPhoneVerification` operation.
public protocol PhoneVerificationAPI: APICapability {
    /// Starts the phone verification flow.
    ///
    /// - Parameter params: Optional verification parameters. When omitted, the API uses values from the current
    ///   ``Context`` where available.
    /// - Returns: ``APIResult/success(_:)`` with the challenge controller, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `startPhoneVerification` operation; `StartVerificationResponse` success response schema.
    func start(params: PhoneVerificationAPIParams?) async -> APIResult<any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>
}

/// Parameters for the phone verification API request.
///
/// - Parameters:
///   - loginID: The phone number to verify. When `nil`, the login ID from the current ``Context`` is used if
///     available. It may be omitted when an access token is supplied or available from the current ``Context``. If the
///     current ``Context`` contains a raw login ID, it must resolve to a supported typed login ID or
///     ``PhoneVerificationAPI/start(params:)`` returns a typed failure.
///     Defaults to `nil`.
///   - loginIDHintID: An optional hint identifier for the login ID. Defaults to `nil`.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. The same token is used by the controller's linked calls. Defaults
///     to `nil`.
///   - verificationMethods: Preferred verification methods (OTP, magic link). When `nil`, the server chooses available
///     methods. Defaults to `nil`.
///   - magicLinkRedirectURL: An optional URL to which the user will be redirected after clicking a magic link, if that
///     verification method is requested and used. Defaults to `nil`.
///
/// OpenAPI source: `StartVerificationRequest` schema.
public struct PhoneVerificationAPIParams: Sendable {
    /// Phone number to verify.
    public let loginID: LoginID?
    /// Optional hint identifier for the login ID.
    public let loginIDHintID: String?
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    /// Preferred verification methods.
    public let verificationMethods: Set<VerificationMethod>?
    /// Redirect URL used if the selected verification method needs a magic-link redirect.
    public let magicLinkRedirectURL: String?
    internal let traceParent: String?

    public init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        verificationMethods: Set<VerificationMethod>? = nil,
        magicLinkRedirectURL: String? = nil
    ) {
        self.init(
            loginID: loginID,
            loginIDHintID: loginIDHintID,
            accessToken: accessToken,
            verificationMethods: verificationMethods,
            magicLinkRedirectURL: magicLinkRedirectURL,
            traceParent: nil
        )
    }

    internal init(
        loginID: LoginID? = nil,
        loginIDHintID: String? = nil,
        accessToken: AccessToken? = nil,
        verificationMethods: Set<VerificationMethod>? = nil,
        magicLinkRedirectURL: String? = nil,
        traceParent: String? = nil
    ) {
        self.loginID = loginID
        self.loginIDHintID = loginIDHintID
        self.accessToken = accessToken
        self.verificationMethods = verificationMethods
        self.magicLinkRedirectURL = magicLinkRedirectURL
        self.traceParent = traceParent
    }
}

/// Controls an active phone verification challenge.
///
/// ``challenge`` includes the available methods, attempt limits, resend policy, and timeout. The SDK does not enforce
/// attempt, resend, or timeout limits locally; the server response for each linked call is returned as that call's
/// typed ``APIResult``.
///
/// Keep the controller strongly referenced while the challenge can still complete, resend, or cancel. Releasing the
/// controller does not cancel the challenge automatically.
///
/// OpenAPI source: `StartVerificationResponse` success response schema, with linked `completePhoneVerification`,
/// `resendPhoneVerification`, and `cancelPhoneVerification` operations.
public protocol PhoneVerificationAPIController: Sendable {
    /// The verification challenge with details such as supported methods and resend policy.
    ///
    /// OpenAPI source: `StartVerificationResponse` schema.
    var challenge: VerificationChallenge { get }

    /// Submits a verification code.
    ///
    /// - Parameter code: The verification code entered by the user.
    /// - Returns: ``APIResult/success(_:)`` with the token produced by verification, which can be an access token or a
    ///   proof token, ``APIResult/failure(_:)`` with a typed failure such as an invalid, expired, exhausted, or
    ///   wrong-code challenge, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `completePhoneVerification` operation; `CompleteVerificationRequest` request schema.
    func completeWithCode(code: String) async -> APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>

    /// Requests a new verification code to be sent.
    ///
    /// - Returns: ``APIResult/success(_:)`` when the resend request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure for server-enforced resend limits, debounce, or provider failures, or ``APIResult/canceled`` if the
    ///   surrounding task is canceled first.
    ///
    /// OpenAPI source: `resendPhoneVerification` operation.
    func resend() async -> APIResult<Void, PhoneVerificationResendAPIFailure>

    /// Cancels the verification flow.
    ///
    /// - Parameter reason: The caller-visible reason for canceling the challenge.
    /// - Returns: ``APIResult/success(_:)`` when the cancel request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first. Canceling the Swift task does
    ///   not cancel the server-side challenge; call this method when the app wants to request challenge cancellation.
    ///
    /// OpenAPI source: `cancelPhoneVerification` operation.
    func cancel(reason: Reason) async -> APIResult<Void, PhoneVerificationCancelAPIFailure>
}

/// Native failure hierarchy returned by ``PhoneVerificationAPI/start(params:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `startPhoneVerification` operation, plus
/// ``PhoneVerificationStartAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `startPhoneVerification` operation.
public enum PhoneVerificationStartAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad verification start request.
    ///
    /// OpenAPI source: `BadVerificationRequestErrorResponse` response component.
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
        /// About: The selected verification channel is unavailable for the login ID.
        ///
        /// End-user: Offer another authentication method or ask the user to update account contact details.
        ///
        /// Developer action: Check account provider data and channel configuration before retrying.
        ///
        /// - Parameter loginID: Login ID for which the selected verification channel is unavailable.
        ///
        /// OpenAPI source: `MissingChannelError` schema.
        case missingChannel(errorCode: ErrorCode, message: String, loginID: LoginID)
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

    /// Bad verification start request.
    ///
    /// OpenAPI source: `BadVerificationRequestErrorResponse` response component.
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
            .badRequest(.missingChannel(let errorCode, _, _)),
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
            .badRequest(.missingChannel(_, let message, _)),
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
        case .badRequest(.missingChannel):
            return "BadRequest.MissingChannel(errorCode=\(errorCode), message=\(message))"
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

/// Native failure hierarchy returned by ``PhoneVerificationAPIController/completeWithCode(code:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `completePhoneVerification` operation, plus
/// ``PhoneVerificationCompleteAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `completePhoneVerification` operation.
public enum PhoneVerificationCompleteAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while completing a verification challenge.
    ///
    /// OpenAPI source: `BadCompleteVerificationRequestErrorResponse` response component.
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
        /// About: The submitted verification code or equivalent challenge proof is incorrect.
        ///
        /// End-user: Ask the user to try again while attempts remain.
        ///
        /// Developer action: Keep the current challenge active and update remaining-attempt UI if available.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `VerificationCodeWrongError` schema.
        case wrongCode(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
        /// About: The server could not map the failure to a more specific public error code.
        ///
        /// End-user: Show a generic failure message and suggest retrying.
        ///
        /// Developer action: Log the correlation context, inspect server logs, and escalate if the issue repeats.
        ///
        /// OpenAPI source: `UnknownError` schema.
        case unknown(errorCode: ErrorCode, message: String)
    }

    /// Bad request while completing a verification challenge.
    ///
    /// OpenAPI source: `BadCompleteVerificationRequestErrorResponse` response component.
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
            .badRequest(.wrongCode(let errorCode, _, _)),
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
            .badRequest(.wrongCode(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .forbidden(_, let message), .unexpected(_, let message, _): return message
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
        case .badRequest(.wrongCode):
            return "BadRequest.WrongCode(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``PhoneVerificationAPIController/resend()``.
///
/// Direct cases correspond to OpenAPI error response components for the `resendPhoneVerification` operation, plus
/// ``PhoneVerificationResendAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `resendPhoneVerification` operation.
public enum PhoneVerificationResendAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while resending a verification challenge code.
    ///
    /// OpenAPI source: `BadResendRequestErrorResponse` response component.
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
        /// About: The verification code resend limit or debounce policy was reached.
        ///
        /// End-user: Ask the user to wait or restart the challenge.
        ///
        /// Developer action: Disable resend UI for the current challenge and respect the server resend policy.
        ///
        /// - Parameter challengeID: The challenge's identifier.
        ///
        /// OpenAPI source: `MaximumResendAttemptsReachedError` schema.
        case maximumResendAttemptsReached(errorCode: ErrorCode, message: String, challengeID: ChallengeID)
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

    /// Bad request while resending a verification challenge code.
    ///
    /// OpenAPI source: `BadResendRequestErrorResponse` response component.
    case badRequest(BadRequest)
    /// Provider or capability dependency failed.
    ///
    /// OpenAPI source: `FailedDependencyErrorResponse` response component.
    case failedDependency(FailedDependency)
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
            .badRequest(.maximumResendAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)),
            .badRequest(.invalidChallenge(_, let message, _)),
            .badRequest(.maximumResendAttemptsReached(_, let message, _)),
            .badRequest(.unknown(_, let message)):
            return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
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
        case .badRequest(.maximumResendAttemptsReached):
            return "BadRequest.MaximumResendAttemptsReached(errorCode=\(errorCode), message=\(message))"
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``PhoneVerificationAPIController/cancel(reason:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `cancelPhoneVerification` operation, plus
/// ``PhoneVerificationCancelAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `cancelPhoneVerification` operation.
public enum PhoneVerificationCancelAPIFailure: APIFailure, CustomStringConvertible {
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
