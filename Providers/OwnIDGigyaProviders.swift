import Foundation
@preconcurrency import Gigya
@_spi(OwnIDInternal) import OwnIDCore

public struct NonSendableBox<T>: @unchecked Sendable {
    public let value: T
    public init(_ value: T) { self.value = value }
}

/// Gigya-backed provider failure returned by provider callbacks.
///
/// `gigyaProviders(gigya:)` returns this type through provider `Result.failure` values. The helper does not throw it
/// directly.
///
/// It can carry:
/// - A plain message/underlying error pair, or
/// - A typed ``LoginApiError`` that can be recovered later.
///
/// ``errorDescription`` resolves in this order: explicit ``message``, `underlyingError.localizedDescription`,
/// fallback `"Gigya error"`.
public struct GigyaException: Error, LocalizedError, Sendable {
    private let boxedLoginApiError: NonSendableBox<Any>?
    /// Optional human-readable message set by the provider implementation.
    public let message: String?
    /// Optional underlying error preserved for diagnostics.
    public let underlyingError: (any Error)?

    public var errorDescription: String? {
        message ?? underlyingError?.localizedDescription ?? "Gigya error"
    }

    /// Creates a failure without a raw ``LoginApiError`` payload.
    ///
    /// - Parameters:
    ///   - message: Optional user-facing/log message.
    ///   - underlyingError: Optional underlying cause.
    public init(message: String? = nil, underlyingError: (any Error)? = nil) {
        self.boxedLoginApiError = nil
        self.message = message
        self.underlyingError = underlyingError
    }

    /// Creates a failure that preserves the raw Gigya login error.
    ///
    /// - Parameters:
    ///   - loginApiError: Raw Gigya login error, including interruption metadata when Gigya provides it.
    ///   - message: Optional override message. Defaults to `loginApiError.error.localizedDescription`.
    ///   - underlyingError: Optional additional underlying cause.
    public init<T: GigyaAccountProtocol>(
        loginApiError: LoginApiError<T>,
        message: String? = nil,
        underlyingError: (any Error)? = nil
    ) {
        self.boxedLoginApiError = NonSendableBox(loginApiError)
        self.message = message ?? loginApiError.error.localizedDescription
        self.underlyingError = underlyingError
    }

    /// Returns the stored raw Gigya login error when it matches `T`.
    ///
    /// - Parameter type: Account schema used by the caller.
    /// - Returns: Matching ``LoginApiError`` or `nil` when no raw login error was stored or the account schema differs.
    public func getLoginApiError<T: GigyaAccountProtocol>(type: T.Type = T.self) -> LoginApiError<T>? {
        boxedLoginApiError?.value as? LoginApiError<T>
    }

    /// Convenience accessor for interruption metadata stored in the raw login error.
    ///
    /// - Parameter for: Account schema used by the caller.
    /// - Returns: Interruption details when available; otherwise `nil`.
    public func interruption<T: GigyaAccountProtocol>(for: T.Type = T.self) -> GigyaInterruptions<T>? {
        getLoginApiError(type: T.self)?.interruption
    }
}

extension OwnIDProvidersRegistrar {
    /// Registers Gigya-backed ``SessionCreate`` and ``PasswordAuthenticate`` providers.
    ///
    /// Register this source-only helper inside a providers block. It depends on the target that compiles it also
    /// compiling and linking Gigya. It is not part of the `OwnIDCore` or `OwnIDSwiftUI` package products and is not a
    /// separate product.
    ///
    /// Use ``OwnID/setProviders(_:)`` to update providers in the current scope,
    /// or ``OwnID/withProviders(_:_:)`` to register Gigya providers only in the returned child scope.
    ///
    /// Treat `sessionPayload`, Gigya session token/secret values, and passwords passed through this helper as sensitive.
    ///
    /// ``SessionCreate`` behavior:
    /// - Treats `sessionPayload` as required OwnID-provided JSON text and expects a top-level JSON object.
    /// - When `sessionInfo` exists, reads `sessionToken`, `sessionSecret`, and an optional positive expiration from
    ///   `expires_in` or `expirationTime`, sets Gigya session, and returns success with
    ///   `SessionOutput(session: gigya.getSession())`.
    /// - When non-empty `errorJson` exists, maps `errorCode` and `errorMessage` when both are present and returns
    ///   failure.
    /// - Missing session fields, malformed JSON, failed `GigyaSession` creation, or any other payload shape return
    ///   failure.
    /// - Does not cancel in-progress payload parsing or Gigya session assignment.
    ///
    /// ``PasswordAuthenticate`` behavior:
    /// - Delegates to `gigya.login(loginId:password:)`.
    /// - Waits for the Gigya callback result.
    /// - Gigya login API does not expose a cancellation handle, so task cancellation does not cancel the
    ///   in-flight Gigya request.
    /// - If the awaiting task is already cancelled, returns `CancellationError`; later callback results have no returned
    ///   result to deliver.
    /// - On success, returns `Result.success(SessionOutput(session: gigya.getSession()))`.
    /// - On failure, returns ``GigyaException`` with the raw `LoginApiError` so callers can inspect interruption metadata.
    ///
    /// Helper and Gigya failures are returned as `Result.failure(GigyaException)`. An already-cancelled
    /// password-authentication task returns `CancellationError`. Provider callbacks are invoked on the main actor by
    /// OwnID; keep additional work asynchronous rather than blocking that actor.
    ///
    /// - Parameter gigya: Gigya core instance used by the session creation and password authentication callbacks.
    public mutating func gigyaProviders<T: GigyaAccountProtocol>(gigya: GigyaCore<T> = Gigya.sharedInstance()) {

        let logger = getOrNil(type: OwnIDLogRouter.self)

        sessionCreate { provider in
            provider.create { [gigya] params in
                do {
                    guard
                        let sessionData = params.sessionPayload.data(using: .utf8),
                        let sessionJson = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any]
                    else {
                        return .failure(GigyaException(message: "Could not parse sessionPayload as a JSON object"))
                    }

                    if let sessionInfoDict = sessionJson["sessionInfo"] as? [String: Any] {
                        guard
                            let sessionToken = sessionInfoDict["sessionToken"] as? String,
                            let sessionSecret = sessionInfoDict["sessionSecret"] as? String
                        else {
                            return .failure(GigyaException(message: "Missing sessionToken or sessionSecret"))
                        }

                        let expiresIn =
                            (sessionInfoDict["expires_in"] as? NSNumber)?.doubleValue
                            ?? (sessionInfoDict["expires_in"] as? String).flatMap(Double.init)
                        let expirationTime =
                            (sessionInfoDict["expirationTime"] as? NSNumber)?.doubleValue
                            ?? (sessionInfoDict["expirationTime"] as? String).flatMap(Double.init)
                        let expiration = (expiresIn ?? 0) > 0 ? (expiresIn ?? 0) : ((expirationTime ?? 0) > 0 ? (expirationTime ?? 0) : 0)

                        guard let gigyaSession = GigyaSession(sessionToken: sessionToken, secret: sessionSecret, expiration: expiration)
                        else {
                            return .failure(GigyaException(message: "sessionCreate: Failed to create GigyaSession"))
                        }

                        gigya.setSession(gigyaSession)
                        return .success(SessionOutput(session: gigya.getSession()))
                    }

                    if let errorJsonString = sessionJson["errorJson"] as? String, errorJsonString.isEmpty == false {
                        if let errorData = errorJsonString.data(using: .utf8),
                            let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any]
                        {
                            let errorCode =
                                (errorJson["errorCode"] as? NSNumber)?.intValue
                                ?? (errorJson["errorCode"] as? String).flatMap(Int.init)
                            let errorMessage = errorJson["errorMessage"] as? String

                            if let errorCode, let errorMessage, errorMessage.isEmpty == false {
                                logger?.logW(source: Self.self, prefix: "sessionCreate", message: "[\(errorCode)] \(errorMessage)")
                                return .failure(GigyaException(message: "sessionCreate: [\(errorCode)] \(errorMessage)"))
                            }
                        }

                        logger?.logW(source: Self.self, prefix: "sessionCreate", message: "Error in response")
                        return .failure(GigyaException(message: "sessionCreate: Error in response"))
                    }

                    logger?.logW(source: Self.self, prefix: "sessionCreate", message: "Unexpected data in sessionPayload")
                    return .failure(GigyaException(message: "sessionCreate: Unexpected JSON shape in sessionPayload", underlyingError: nil))
                } catch {
                    logger?.logW(
                        source: Self.self,
                        prefix: "sessionCreate",
                        message: "Gigya sessionCreate failed: \(error.localizedDescription)",
                        cause: error
                    )
                    return .failure(GigyaException(message: "sessionCreate error: \(error.localizedDescription)", underlyingError: error))
                }
            }
        }

        passwordAuthenticate { provider in
            provider.authenticate { [gigya] params in
                guard !Task.isCancelled else { return .failure(CancellationError()) }

                let stream = AsyncStream<Result<SessionOutput, any Error & Sendable>> { continuation in
                    gigya.login(loginId: params.loginID.id, password: params.password) { (result: GigyaLoginResult<T>) in
                        let returning: Result<SessionOutput, any Error & Sendable> =
                            switch result {
                            case .success:
                                .success(SessionOutput(session: gigya.getSession()))
                            case .failure(let loginApiError):
                                .failure(GigyaException(loginApiError: loginApiError, message: loginApiError.error.localizedDescription))
                            }
                        continuation.yield(returning)
                        continuation.finish()
                    }
                }

                for await result in stream { return result }
                return .failure(CancellationError())
            }
        }
    }
}
