import Foundation

/// Starts an OpenID Connect authentication flow.
///
/// Use this API when the app drives the social-provider UI itself and needs OwnID only for the challenge lifecycle.
/// ``start(params:)`` returns a controller that carries the provider challenge, accepts the provider result, and can
/// cancel the challenge when the app abandons the flow.
///
/// Calling ``start(params:)`` creates a server-side challenge only; the app owns provider UI, provider tokens/codes,
/// and any session exchange after completion.
///
/// OpenAPI source: `startOidcChallenge` operation.
public protocol OIDCAPI: APICapability {
    /// Starts the OIDC authentication flow.
    ///
    /// - Parameter params: Optional OIDC parameters. When omitted, the provider defaults to
    ///   ``SocialProviderID/apple``, the response type defaults to ``OAuthResponseType/idToken``, and the access token
    ///   uses the current ``Context`` where available.
    /// - Returns: ``APIResult/success(_:)`` with the challenge controller, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `startOidcChallenge` operation; `OidcChallengeResponse` success response schema.
    func start(params: OIDCAPIParams?) async -> APIResult<any OIDCAPIController, OIDCStartAPIFailure>
}

/// Parameters for starting an OIDC challenge.
///
/// The public direct API exposes provider, response type, and optional session access token only. Login ID hints and
/// redirect URI overrides are SDK-owned flow details and are not configurable through this public parameter object.
///
/// - Parameters:
///   - provider: Social identity provider to use. When `nil`, OwnID starts an Apple challenge.
///   - oauthResponseType: Provider result type the app will later pass back to the controller. Use
///     ``OAuthResponseType/idToken`` with ``OIDCAPIController/completeWithToken(idToken:)`` and
///     ``OAuthResponseType/code`` with ``OIDCAPIController/completeWithCode(code:)``.
///   - accessToken: Optional token for an already-authenticated session. The app owns this sensitive value. When `nil`,
///     OwnID uses the current ``Context`` access token when one is available. The same token is used for this
///     challenge's start, complete, and cancel requests and is not persisted by the SDK.
///
/// OpenAPI source: `StartOidcChallengeRequest` schema.
public struct OIDCAPIParams: Sendable {
    /// Social identity provider to use for the challenge.
    public let provider: SocialProviderID?
    /// OAuth response type expected from the provider flow.
    public let oauthResponseType: OAuthResponseType
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    public init(
        provider: SocialProviderID? = nil,
        oauthResponseType: OAuthResponseType = .idToken,
        accessToken: AccessToken? = nil
    ) {
        self.init(provider: provider, oauthResponseType: oauthResponseType, accessToken: accessToken, traceParent: nil)
    }

    internal init(
        provider: SocialProviderID? = nil,
        oauthResponseType: OAuthResponseType = .idToken,
        accessToken: AccessToken? = nil,
        traceParent: String? = nil
    ) {
        self.provider = provider
        self.oauthResponseType = oauthResponseType
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Controls an active OIDC authentication challenge.
///
/// Use ``challenge`` to start the provider flow in your app. After the provider finishes, call the completion method
/// that matches the ``OIDCAPIParams/oauthResponseType`` used to start this controller. A successful completion returns
/// the OwnID ``AccessTokenWithUserInfo`` for the authenticated user. Call ``cancel(reason:)`` when the app stops the
/// provider flow without a provider result.
///
/// Calling the completion method that does not match the requested response type fails locally with
/// ``OIDCCompleteAPIFailure/badRequest(_:)``. Keep the controller strongly referenced while the challenge can still
/// complete or cancel. Releasing the controller does not cancel the challenge automatically.
///
/// Canceling the surrounding task is not the same as canceling the OIDC challenge; call ``cancel(reason:)`` when the app
/// abandons the provider flow.
///
/// OpenAPI source: `OidcChallengeResponse` success response schema, with linked `completeOidcChallenge` and
/// `cancelOidcVerification` operations.
public protocol OIDCAPIController: Sendable {
    /// The provider challenge the app must use to launch social authentication.
    ///
    /// The challenge includes the OwnID challenge identifier, expiration timeout, provider client ID, and optional web
    /// challenge URL. The app owns presenting or invoking the provider flow with those values.
    ///
    /// OpenAPI source: `OidcChallengeResponse` schema.
    var challenge: SocialChallenge { get }

    /// Completes authentication with an ID token returned by the provider.
    ///
    /// Use this when the controller was started with ``OAuthResponseType/idToken``. On success, the returned
    /// ``AccessTokenWithUserInfo`` contains the OwnID access token plus the login ID, provider, and provider user info.
    /// The app owns the provider ID token it passes in and the OwnID token returned on success.
    /// When this controller expects an authorization code, this function returns
    /// ``OIDCCompleteAPIFailure/badRequest(_:)``.
    ///
    /// - Parameter idToken: The ID token returned by the provider.
    /// - Returns: ``APIResult/success(_:)`` with the completed sign-in result, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `completeOidcChallenge` operation; `CompleteOidcChallengeRequest` request schema.
    func completeWithToken(idToken: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure>

    /// Completes authentication with an authorization code returned by the provider.
    ///
    /// Use this when the controller was started with ``OAuthResponseType/code``. On success, the returned
    /// ``AccessTokenWithUserInfo`` contains the OwnID access token plus the login ID, provider, and provider user info.
    /// The app owns the provider code it passes in and the OwnID token returned on success.
    /// When this controller expects an ID token, this function returns ``OIDCCompleteAPIFailure/badRequest(_:)``.
    ///
    /// - Parameter code: The authorization code returned by the provider.
    /// - Returns: ``APIResult/success(_:)`` with the completed sign-in result, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `completeOidcChallenge` operation; `CompleteOidcChallengeRequest` request schema.
    func completeWithCode(code: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure>

    /// Cancels the active OIDC challenge with an app-selected ``Reason``.
    ///
    /// Use this when the user closes the provider UI, the app moves to another challenge, or the app otherwise
    /// abandons the flow. A successful result means OwnID accepted the cancel request; it does not dismiss provider UI
    /// that the app owns. Invalid, expired, or already completed challenges are reported through
    /// ``OIDCCancelAPIFailure``.
    ///
    /// - Parameter reason: The caller-visible reason for canceling the challenge.
    /// - Returns: ``APIResult/success(_:)`` when the cancel request is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `cancelOidcVerification` operation.
    func cancel(reason: Reason) async -> APIResult<Void, OIDCCancelAPIFailure>
}

/// Native failure hierarchy returned by ``OIDCAPI/start(params:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `startOidcChallenge` operation, plus
/// ``OIDCStartAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `startOidcChallenge` operation.
public enum OIDCStartAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request.
    ///
    /// OpenAPI source: `BadRequestErrorResponse` response component.
    public enum BadRequest: Sendable {
        /// About: The request payload, route parameter, query parameter, or operation state is invalid.
        ///
        /// End-user: Not Applicable
        ///
        /// Developer action: Validate the request has all the required fields in their expected format.
        ///
        /// OpenAPI source: `InvalidArgumentError` schema.
        case invalidArgument(errorCode: ErrorCode, message: String)
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
    /// OpenAPI source: `BadRequestErrorResponse` response component.
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
        case .badRequest(.invalidArgument(let errorCode, _)), .badRequest(.unknown(let errorCode, _)): return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .maximumChallengesReached(let errorCode, _): return errorCode
        case .forbidden(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)), .badRequest(.unknown(_, let message)): return message
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

/// Failure returned by ``OIDCAPIController/completeWithToken(idToken:)`` or
/// ``OIDCAPIController/completeWithCode(code:)``.
///
/// OpenAPI source: `completeOidcChallenge` operation.
public enum OIDCCompleteAPIFailure: APIFailure, CustomStringConvertible {
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
            .badRequest(.maximumAttemptsReached(let errorCode, _, _)),
            .badRequest(.unknown(let errorCode, _)):
            return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
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
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
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
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Native failure hierarchy returned by ``OIDCAPIController/cancel(reason:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `cancelOidcVerification` operation, plus
/// ``OIDCCancelAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `cancelOidcVerification` operation.
public enum OIDCCancelAPIFailure: APIFailure, CustomStringConvertible {
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
        case .badRequest(.unknown):
            return "BadRequest.Unknown(errorCode=\(errorCode), message=\(message))"
        case .forbidden:
            return "Forbidden(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
