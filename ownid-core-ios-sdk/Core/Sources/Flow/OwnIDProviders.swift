import Foundation

/// Represents different types of providers used for OwnID authentication flow.
///
/// Providers manage critical components such as session handling and authentication mechanisms, including traditional password-based logins.
///
/// They allow developers to define how users are authenticated, how sessions are maintained and how accounts are managed within the application.
/// 
/// Define providers globally using ``OwnID/providers(_:)`` or override them for specific flows if required using ``OwnID/start(_:)``.
public protocol ProviderProtocol { }

/// The Session Provider is responsible for creating user sessions.
public protocol SessionProviderProtocol: ProviderProtocol {
    /// Implement function to create a user session using the provided data and return an ``OwnID/AuthResult`` indicating whether the session creation was successful or not.
    /// - Parameters:
    ///   - loginId: The user's login identifier.
    ///   - session: Raw session data received from the OwnID.
    ///   - authToken: OwnID authentication token associated with the session.
    ///   - authMethod: Type of authentication used for the session (optional).
    /// - Returns: ``OwnID/AuthResult`` with the result of the session creation operation.
    func create(loginId: String, session: [String: Any], authToken: String, authMethod: OwnID.CoreSDK.AuthMethod?) async -> OwnID.AuthResult
}

/// The Account Provider manages account creation.
public protocol AccountProviderProtocol: ProviderProtocol {
    /// Implement function to registers a new account with the given loginId and profile information.
    /// - Parameters:
    ///   - loginId: The user's login identifier.
    ///   - profile: Raw profile data received from the OwnID.
    ///   - ownIdData: Optional data associated with the user.
    ///   - authToken: OwnID authentication token associated with the session (optional).
    /// - Returns: ``OwnID/AuthResult`` with the result of the session creation operation.
    func register(loginId: String, profile: [String: Any], ownIdData: [String: Any]?, authToken: String?) async -> OwnID.AuthResult
}

/// The Authentication Provider manages various authentication mechanisms.
public protocol AuthProviderProtocol: ProviderProtocol { }

/// Provides password-based authentication functionality.
public protocol PasswordProviderProtocol: AuthProviderProtocol {
    /// Implement function to authenticates user with the given loginId and password.
    /// - Parameters:
    ///   - loginId: The user's login identifier.
    ///   - password: The user's password.
    /// - Returns: ``OwnID/AuthResult`` with the result of the session creation operation.
    func authenticate(loginId: String, password: String) async -> OwnID.AuthResult
}
