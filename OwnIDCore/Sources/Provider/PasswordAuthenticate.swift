import Foundation

/// Parameters supplied to ``PasswordAuthenticate``.
public struct PasswordAuthenticateParams: CapabilityParams, Sendable {
    /// The user's login identifier.
    public let loginID: LoginID
    /// The user's password. Treat it as sensitive credential material and never log it.
    public let password: String

    /// Creates password authentication parameters.
    ///
    /// - Parameters:
    ///   - loginID: User login identifier.
    ///   - password: User password. Treat it as sensitive credential material and never log it.
    public init(loginID: LoginID, password: String) {
        self.loginID = loginID
        self.password = password
    }
}

/// App-owned provider that authenticates a user with a login identifier and password.
///
/// OwnID invokes this provider on the main actor. Register via ``OwnID/setProviders(_:)`` or
/// ``OwnID/withProviders(_:_:)``.
///
/// The app owns password verification, session creation, and the meaning of failures returned from
/// ``authenticate(params:)``.
public protocol PasswordAuthenticate: Capability, Sendable {
    /// Returns whether password authentication can run for the provided parameters.
    ///
    /// OwnID invokes this availability check with ``PasswordAuthenticateParams`` on the main actor before
    /// ``authenticate(params:)``. A `nil` value is a general readiness check without credential data. The default
    /// implementation returns `true`; implementations that require ``PasswordAuthenticateParams`` should return `false`
    /// for `nil` or unsupported parameter types.
    ///
    /// - Parameter params: Optional password authentication parameters. `nil` means no parameter-specific check is
    ///   requested.
    /// - Returns: `true` when password authentication can run, otherwise `false`.
    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool

    /// Authenticates a user with the given login identifier and password.
    ///
    /// Verify credentials at the app's authentication boundary and return `Result.success` with ``SessionOutput`` when
    /// authentication succeeds. Return `Result.failure` for invalid credentials or integration failures. OwnID does not
    /// retry this callback or persist the returned ``SessionOutput``.
    ///
    /// - Parameter params: Password authentication parameters.
    /// - Returns: `Result` with ``SessionOutput`` on success, or an error on failure.
    @MainActor func authenticate(params: PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable>
}

extension PasswordAuthenticate {
    @MainActor public func isAvailable(params: (any CapabilityParams)?) async -> Bool { true }
}
