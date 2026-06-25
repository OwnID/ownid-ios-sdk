import Foundation

/// Starts login discovery for a user identifier.
///
/// Use this direct API when the app has a ``LoginID`` but does not yet have an OwnID ``AccessToken``. The login ID is
/// taken from ``DiscoverAPIParams/loginID``, or from the scoped ``Context`` when the parameter is omitted.
///
/// A successful API result contains ``LoginResponse``. ``LoginResponse/success(_:)`` gives the app-owned data needed to
/// create the app session. No-session outcomes mean OwnID did not return a session payload; handle the specific outcome
/// by continuing the required authentication, account-not-found, or account-blocked path.
///
/// Calling ``start(params:)`` sends a direct API request only; it does not create an operation, present UI, persist
/// tokens, or create the app session.
///
/// OpenAPI source: `login` operation.
public protocol DiscoverAPI: APICapability {
    /// Starts login discovery.
    ///
    /// - Parameter params: Optional parameters. Omit only when the scoped ``Context`` contains the login ID to discover.
    /// - Returns: ``APIResult/success(_:)`` with the login outcome, ``APIResult/failure(_:)`` with a typed failure, or
    ///   ``APIResult/canceled`` if the surrounding task is canceled before completion.
    ///
    /// OpenAPI source: `login` operation; `LoginResponse` and `AuthRequiredResponse` success response schemas.
    func start(params: DiscoverAPIParams?) async -> APIResult<LoginResponse, DiscoverAPIFailure>
}

/// Parameters for login discovery.
///
/// - Parameters:
///   - loginID: Login identifier to discover. When `nil`, the SDK uses the login ID from the scoped ``Context`` if one
///     is available. Calling discover without a resolvable login ID completes with
///     ``DiscoverAPIFailure/badRequest(_:)``. Unsupported or invalid scoped login IDs complete with the matching bad
///     request branch.
///
/// OpenAPI source: `LoginRequest` schema.
public struct DiscoverAPIParams: Sendable {
    /// Login identifier to discover authentication requirements for.
    public let loginID: LoginID?
    internal let traceParent: String?

    public init(loginID: LoginID? = nil) {
        self.init(loginID: loginID, traceParent: nil)
    }

    internal init(loginID: LoginID? = nil, traceParent: String? = nil) {
        self.loginID = loginID
        self.traceParent = traceParent
    }
}

/// Native failure hierarchy returned by ``DiscoverAPI/start(params:)``.
///
/// Direct cases correspond to OpenAPI error response components for the `login` operation, plus
/// ``DiscoverAPIFailure/unexpected(errorCode:message:underlyingError:)`` for SDK-side failures.
///
/// OpenAPI source: `login` operation.
public enum DiscoverAPIFailure: APIFailure, CustomStringConvertible {
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
        case .unexpected:
            return "Unexpected(errorCode=\(errorCode), message=\(message))"
        }
    }
}
