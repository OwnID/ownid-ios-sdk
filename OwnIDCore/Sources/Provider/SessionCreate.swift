import Foundation

/// Parameters supplied to ``SessionCreate`` after OwnID authentication succeeds.
public struct SessionCreateParams: CapabilityParams, Sendable {
    /// The authenticated user's login identifier.
    public let loginID: LoginID
    /// OwnID access token associated with this authentication. Treat it as sensitive and avoid logging or persisting it
    /// unless your session boundary requires it.
    public let accessToken: AccessToken
    /// Authentication method associated with the OwnID authentication result.
    public let authMethod: AuthMethod
    /// Server-provided host session payload. Structured values remain JSON text. If the server returns a plain string,
    /// this property contains that string value. Treat it as sensitive session material.
    public let sessionPayload: String

    /// Creates session creation parameters.
    ///
    /// - Parameters:
    ///   - loginID: Authenticated login identifier.
    ///   - accessToken: OwnID access token associated with this authentication. Treat it as sensitive and avoid logging
    ///     or persisting it unless your session boundary requires it.
    ///   - authMethod: Authentication method associated with the OwnID authentication result.
    ///   - sessionPayload: Server-provided host session payload. Structured values remain JSON text. If the server
    ///     returns a plain string, this property contains that string value. Treat it as sensitive session material.
    public init(loginID: LoginID, accessToken: AccessToken, authMethod: AuthMethod, sessionPayload: String) {
        self.loginID = loginID
        self.accessToken = accessToken
        self.authMethod = authMethod
        self.sessionPayload = sessionPayload
    }
}

/// App-owned provider that creates a host session after successful OwnID authentication.
///
/// OwnID invokes this provider on the main actor. Register via ``OwnID/setProviders(_:)`` or
/// ``OwnID/withProviders(_:_:)``.
///
/// The app owns session creation, token exchange, persistence, and the meaning of failures returned from
/// ``create(params:)``.
public protocol SessionCreate: Capability, Sendable {
    /// Returns whether session creation can run for the provided parameters.
    ///
    /// OwnID invokes this availability check with ``SessionCreateParams`` on the main actor before
    /// ``create(params:)``. A `nil` value is a general readiness check without session-specific data. The default
    /// implementation returns `true`; implementations that require ``SessionCreateParams`` should return `false` for
    /// `nil` or unsupported parameter types.
    ///
    /// - Parameter params: Optional session creation parameters. `nil` means no parameter-specific check is requested.
    /// - Returns: `true` when session creation can run, otherwise `false`.
    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool

    /// Creates host session output for an authenticated user.
    ///
    /// Use ``SessionCreateParams/accessToken`` and ``SessionCreateParams/sessionPayload`` at the app's authentication
    /// boundary to create or refresh the host session. Return `Result.success` with ``SessionOutput`` when session
    /// creation succeeds, or `Result.failure` when it fails. OwnID does not retry this callback or persist the returned
    /// ``SessionOutput``.
    ///
    /// - Parameter params: Session creation parameters.
    /// - Returns: `Result` with ``SessionOutput`` on success, or an error on failure.
    @MainActor func create(params: SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable>
}

extension SessionCreate {
    @MainActor public func isAvailable(params: (any CapabilityParams)?) async -> Bool { true }
}
