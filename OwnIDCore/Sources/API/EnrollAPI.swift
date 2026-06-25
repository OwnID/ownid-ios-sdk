import Foundation

/// Enrolls a passkey for an authenticated user using a proof token.
///
/// The proof token comes from a successful passkey attestation verification. The optional access token identifies the
/// authenticated account; when it is `nil`, the SDK uses the access token from the current ``Context`` if available.
/// If neither source has an access token, ``start(params:)`` returns
/// ``PasskeyEnrollAPIFailure/badRequest(_:)`` before sending the request.
///
/// Success means the backend accepted enrollment and returned no response payload.
///
/// OpenAPI source: `attestationEnroll` operation.
public protocol PasskeyEnrollAPI: APICapability {
    /// Starts the passkey enrollment.
    ///
    /// - Parameter params: Enrollment parameters, including the proof token that authorizes enrollment.
    /// - Returns: ``APIResult/success(_:)`` when enrollment is accepted, ``APIResult/failure(_:)`` with a typed
    ///   failure, or ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `attestationEnroll` operation.
    func start(params: PasskeyEnrollAPIParams) async -> APIResult<Void, PasskeyEnrollAPIFailure>
}

/// Parameters for the passkey enrollment API request.
///
/// - Parameters:
///   - proofToken: Proof token returned by passkey attestation verification.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. Defaults to `nil`.
///
/// OpenAPI source: `AttestationEnrollRequest` schema.
public struct PasskeyEnrollAPIParams: Sendable {
    /// Proof token returned by passkey attestation verification.
    public let proofToken: ProofToken
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    public init(proofToken: ProofToken, accessToken: AccessToken? = nil) {
        self.init(proofToken: proofToken, accessToken: accessToken, traceParent: nil)
    }

    internal init(proofToken: ProofToken, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.proofToken = proofToken
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Native failure hierarchy returned by ``PasskeyEnrollAPI/start(params:)``.
///
/// Endpoint-defined failures include invalid enrollment input, forbidden enrollment, missing user, and provider or
/// capability dependency failures. ``PasskeyEnrollAPIFailure/unexpected(errorCode:message:underlyingError:)``
/// represents transport failures, local runtime failures, and endpoint responses that cannot be represented by a typed
/// case.
///
/// OpenAPI source: `attestationEnroll` operation.
public enum PasskeyEnrollAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while validating the passkey enrollment proof token or request.
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
        /// About: A configured backend provider failed while OwnID was processing the operation.
        ///
        /// End-user: Show a temporary failure message.
        ///
        /// Developer action: Log provider request context, monitor the provider integration, and escalate repeated failures.
        ///
        /// - Parameter scope: Provider or capability scope associated with the dependency failure.
        ///
        /// OpenAPI source: `ProviderError` schema.
        case providerFailed(errorCode: ErrorCode, message: String, scope: APIFailureScope)
        /// About: No provider is configured for a capability required by the operation.
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

    /// Bad enrollment request.
    case badRequest(BadRequest)
    /// About: The endpoint rejected authorization for this enrollment.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check that a valid access token is supplied by parameters or ``Context`` and has the claims
    /// required by the operation's policy.
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
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error, or
    /// unexpected endpoint response.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for network, endpoint contract, or
    /// SDK runtime issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)), .badRequest(.unknown(let errorCode, _)): return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .forbidden(let errorCode, _), .userNotFound(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)), .badRequest(.unknown(_, let message)): return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
            return message
        case .forbidden(_, let message), .userNotFound(_, let message), .unexpected(_, let message, _): return message
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
        case .userNotFound:
            return "UserNotFound(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Enrolls an email address for an authenticated user using a proof token.
///
/// The proof token comes from a completed email verification challenge. The optional access token identifies the
/// authenticated account; when it is `nil`, the SDK uses the access token from the current ``Context`` if available. If
/// neither source has an access token, ``start(params:)`` returns ``EmailEnrollAPIFailure/badRequest(_:)`` before
/// sending the request.
///
/// Success means the backend accepted enrollment and returned no response payload.
///
/// OpenAPI source: `enrollEmailAddress` operation.
public protocol EmailEnrollAPI: APICapability {
    /// Starts the email enrollment.
    ///
    /// - Parameter params: Enrollment parameters, including the proof token from email verification.
    /// - Returns: ``APIResult/success(_:)`` when enrollment is accepted, ``APIResult/failure(_:)`` with a typed failure, or
    ///   ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `enrollEmailAddress` operation.
    func start(params: EmailEnrollAPIParams) async -> APIResult<Void, EmailEnrollAPIFailure>
}

/// Parameters for the email enrollment API request.
///
/// - Parameters:
///   - proofToken: Proof token returned by completing an email verification challenge.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. Defaults to `nil`.
///
/// OpenAPI source: `EnrollRequest` schema.
public struct EmailEnrollAPIParams: Sendable {
    /// Proof token returned by completing an email verification challenge.
    public let proofToken: ProofToken
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    public init(proofToken: ProofToken, accessToken: AccessToken? = nil) {
        self.init(proofToken: proofToken, accessToken: accessToken, traceParent: nil)
    }

    internal init(proofToken: ProofToken, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.proofToken = proofToken
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Native failure hierarchy returned by ``EmailEnrollAPI/start(params:)``.
///
/// Endpoint-defined failures include invalid enrollment input, forbidden enrollment, missing user, and provider or
/// capability dependency failures. ``EmailEnrollAPIFailure/unexpected(errorCode:message:underlyingError:)`` represents
/// transport failures, local runtime failures, and endpoint responses that cannot be represented by a typed case.
///
/// OpenAPI source: `enrollEmailAddress` operation.
public enum EmailEnrollAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while validating the email enrollment proof token or request.
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
        /// About: A configured backend provider failed while OwnID was processing the operation.
        ///
        /// End-user: Show a temporary failure message.
        ///
        /// Developer action: Log provider request context, monitor the provider integration, and escalate repeated failures.
        ///
        /// - Parameter scope: Provider or capability scope associated with the dependency failure.
        ///
        /// OpenAPI source: `ProviderError` schema.
        case providerFailed(errorCode: ErrorCode, message: String, scope: APIFailureScope)
        /// About: No provider is configured for a capability required by the operation.
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

    /// Bad enrollment request.
    case badRequest(BadRequest)
    /// About: The endpoint rejected authorization for this enrollment.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check that a valid access token is supplied by parameters or ``Context`` and has the claims
    /// required by the operation's policy.
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
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error, or
    /// unexpected endpoint response.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for network, endpoint contract, or
    /// SDK runtime issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)), .badRequest(.unknown(let errorCode, _)): return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .forbidden(let errorCode, _), .userNotFound(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)), .badRequest(.unknown(_, let message)): return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
            return message
        case .forbidden(_, let message), .userNotFound(_, let message), .unexpected(_, let message, _): return message
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
        case .userNotFound:
            return "UserNotFound(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}

/// Enrolls a phone number for an authenticated user using a proof token.
///
/// The proof token comes from a completed phone verification challenge. The optional access token identifies the
/// authenticated account; when it is `nil`, the SDK uses the access token from the current ``Context`` if available. If
/// neither source has an access token, ``start(params:)`` returns ``PhoneEnrollAPIFailure/badRequest(_:)`` before
/// sending the request.
///
/// Success means the backend accepted enrollment and returned no response payload.
///
/// OpenAPI source: `enrollPhoneNumber` operation.
public protocol PhoneEnrollAPI: APICapability {
    /// Starts the phone enrollment.
    ///
    /// - Parameter params: Enrollment parameters, including the proof token from phone verification.
    /// - Returns: ``APIResult/success(_:)`` when enrollment is accepted, ``APIResult/failure(_:)`` with a typed failure, or
    ///   ``APIResult/canceled`` if the surrounding task is canceled first.
    ///
    /// OpenAPI source: `enrollPhoneNumber` operation.
    func start(params: PhoneEnrollAPIParams) async -> APIResult<Void, PhoneEnrollAPIFailure>
}

/// Parameters for the phone enrollment API request.
///
/// - Parameters:
///   - proofToken: Proof token returned by completing a phone verification challenge.
///   - accessToken: An optional access token for an already-authenticated session. When `nil`, the access token from
///     the current ``Context`` is used if available. Defaults to `nil`.
///
/// OpenAPI source: `EnrollRequest` schema.
public struct PhoneEnrollAPIParams: Sendable {
    /// Proof token returned by completing a phone verification challenge.
    public let proofToken: ProofToken
    /// Access token for an already-authenticated session.
    public let accessToken: AccessToken?
    internal let traceParent: String?

    public init(proofToken: ProofToken, accessToken: AccessToken? = nil) {
        self.init(proofToken: proofToken, accessToken: accessToken, traceParent: nil)
    }

    internal init(proofToken: ProofToken, accessToken: AccessToken? = nil, traceParent: String? = nil) {
        self.proofToken = proofToken
        self.accessToken = accessToken
        self.traceParent = traceParent
    }
}

/// Native failure hierarchy returned by ``PhoneEnrollAPI/start(params:)``.
///
/// Endpoint-defined failures include invalid enrollment input, forbidden enrollment, missing user, and provider or
/// capability dependency failures. ``PhoneEnrollAPIFailure/unexpected(errorCode:message:underlyingError:)`` represents
/// transport failures, local runtime failures, and endpoint responses that cannot be represented by a typed case.
///
/// OpenAPI source: `enrollPhoneNumber` operation.
public enum PhoneEnrollAPIFailure: APIFailure, CustomStringConvertible {
    /// Bad request while validating the phone enrollment proof token or request.
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
        /// About: A configured backend provider failed while OwnID was processing the operation.
        ///
        /// End-user: Show a temporary failure message.
        ///
        /// Developer action: Log provider request context, monitor the provider integration, and escalate repeated failures.
        ///
        /// - Parameter scope: Provider or capability scope associated with the dependency failure.
        ///
        /// OpenAPI source: `ProviderError` schema.
        case providerFailed(errorCode: ErrorCode, message: String, scope: APIFailureScope)
        /// About: No provider is configured for a capability required by the operation.
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

    /// Bad enrollment request.
    case badRequest(BadRequest)
    /// About: The endpoint rejected authorization for this enrollment.
    ///
    /// End-user: Explain that the action is unavailable or expired.
    ///
    /// Developer action: Check that a valid access token is supplied by parameters or ``Context`` and has the claims
    /// required by the operation's policy.
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
    /// About: The SDK could not produce a typed API failure because of a transport failure, runtime error, or
    /// unexpected endpoint response.
    ///
    /// End-user: Show a generic failure message and suggest retrying when appropriate.
    ///
    /// Developer action: Log the failure with request and correlation context. Check for network, endpoint contract, or
    /// SDK runtime issues. Escalate repeated occurrences.
    case unexpected(errorCode: ErrorCode, message: String, underlyingError: any Error & Sendable)

    public var errorCode: ErrorCode {
        switch self {
        case .badRequest(.invalidArgument(let errorCode, _)), .badRequest(.unknown(let errorCode, _)): return errorCode
        case .failedDependency(.providerFailed(let errorCode, _, _)), .failedDependency(.missingProvider(let errorCode, _, _, _)):
            return errorCode
        case .forbidden(let errorCode, _), .userNotFound(let errorCode, _): return errorCode
        case .unexpected(let errorCode, _, _): return errorCode
        }
    }

    public var message: String {
        switch self {
        case .badRequest(.invalidArgument(_, let message)), .badRequest(.unknown(_, let message)): return message
        case .failedDependency(.providerFailed(_, let message, _)), .failedDependency(.missingProvider(_, let message, _, _)):
            return message
        case .forbidden(_, let message), .userNotFound(_, let message), .unexpected(_, let message, _): return message
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
        case .userNotFound:
            return "UserNotFound(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.providerFailed):
            return "FailedDependency.ProviderFailed(errorCode=\(errorCode), message=\(message))"
        case .failedDependency(.missingProvider):
            return "FailedDependency.MissingProvider(errorCode=\(errorCode), message=\(message))"
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
