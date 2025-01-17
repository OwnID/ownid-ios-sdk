import Foundation
import Combine
import SwiftUI

extension OwnID {
    /// Holds instances of different OwnID providers.
    public class Providers {
        public var session: SessionProviderProtocol?
        public var account: AccountProviderProtocol?
        public var auths: [AuthProviderProtocol] = []
        public var logo: LogoProviderProtocol?
        
        init(session: SessionProviderProtocol? = nil,
             account: AccountProviderProtocol? = nil,
             auths: [AuthProviderProtocol] = [],
             logo: LogoProviderProtocol? = nil) {
            self.session = session
            self.account = account
            self.auths = auths
            self.logo = logo
        }
        
        func toWrappers() -> [any FlowWrapper] {
            var wrappers: [any FlowWrapper] = []
            
            if let session {
                wrappers.append(SessionProviderWrapper(provider: session))
            }
            if let account {
                wrappers.append(AccountProviderWrapper(provider: account))
            }
            auths.forEach { auth in
                if let auth = auth as? PasswordProviderProtocol {
                    wrappers.append(AuthPasswordWrapper(provider: auth))
                }
            }
            
            return wrappers
        }
    }
}

extension OwnID {
    /// Builder class for configuring ``Providers``
    ///
    /// This builder allows you to define different types of providers such as session, account, and authentication methods that will be used during the OwnID Elite flow.
    public class ProvidersBuilder {
        private var sessionProvider: SessionProviderProtocol?
        private var accountProvider: AccountProviderProtocol?
        private var authProviders: [AuthProviderProtocol] = []
        private var logoProvider: LogoProviderProtocol?
        
        /// Configures the session provider using a ``OwnID/SessionProviderBuilder``.
        /// - Parameter block: A closure that configures the session provider.
        public func session(block: (SessionProviderBuilder) -> Void) {
            let builder = SessionProviderBuilder()
            block(builder)
            sessionProvider = builder.build()
        }
        
        /// Configures the account provider using an ``OwnID/AccountProviderBuilder``.
        /// - Parameter block: A closure that configures the account provider.
        public func account(block: (AccountProviderBuilder) -> Void) {
            let builder = AccountProviderBuilder()
            block(builder)
            accountProvider = builder.build()
        }
        
        /// Configures the authentication providers using an ``OwnID/AuthProvidersBuilder``.
        /// - Parameter block: A closure that configures the authentication providers.
        public func auth(block: (AuthProvidersBuilder) -> Void) {
            let builder = AuthProvidersBuilder()
            block(builder)
            authProviders.append(builder.build())
        }
        
        /// Configures the logo provider
        /// - Parameter block: A closure that configures the logo provider.
        public func logo(block: @escaping (_ logoURL: URL?) -> AnyPublisher<Image?, Never>) {
            logoProvider = LogoProvider(logoClosure: block)
        }
        
        /// Builds the ``OwnID/Providers`` instance.
        /// - Returns: The ``OwnID/Providers`` instance.
        public func build() -> Providers {
            return OwnID.Providers(session: sessionProvider, account: accountProvider, auths: authProviders, logo: logoProvider)
        }
    }
    
    /// Builder class for configuring the session provider.
    ///
    /// This builder allows you to define how sessions are created.
    public class SessionProviderBuilder {
        private var createSession: ((_ loginId: String,
                                     _ session: [String: Any],
                                     _ authToken: String,
                                     _ authMethod: OwnID.CoreSDK.AuthMethod?) async -> AuthResult)?
        
        /// Defines how sessions are created.
        /// 
        /// Implement function to create a user session using the provided data and return a ``OwnID/AuthResult`` indicating whether the session creation was successful or not.
        /// - Parameter block: The closure to be executed upon completion. Closure parameters: **loginId** - The user's login identifier; **session** - raw session data received from the OwnID; **authToken** - OwnID authentication token associated with the session; **authMethod** - type of authentication used for the session (optional); returns ``OwnID/AuthResult`` with the result of the session creation operation.
        public func create(block: @escaping (_ loginId: String,
                                             _ session: [String: Any],
                                             _ authToken: String,
                                             _ authMethod: OwnID.CoreSDK.AuthMethod?) async -> AuthResult) {
            createSession = block
        }
        
        /// Builds the ``SessionProviderProtocol`` instance.
        /// - Returns: The ``SessionProviderProtocol`` instance.
        func build() -> SessionProviderProtocol {
            return SessionProvider(createSession: createSession)
        }
        
        private class SessionProvider: SessionProviderProtocol {
            private let createSession: ((_ loginId: String,
                                         _ session: [String: Any],
                                         _ authToken: String,
                                         _ authMethod: OwnID.CoreSDK.AuthMethod?) async -> AuthResult)?
            
            init(createSession: ((_ loginId: String,
                                  _ session: [String: Any],
                                  _ authToken: String,
                                  _ authMethod: OwnID.CoreSDK.AuthMethod?) async -> AuthResult)?) {
                self.createSession = createSession
            }
            
            func create(loginId: String, session: [String: Any], authToken: String, authMethod: OwnID.CoreSDK.AuthMethod?) async -> AuthResult {
                return await createSession?(loginId, session, authToken, authMethod) ?? .fail(reason: "Session creation block not provided")
            }
        }
    }
    
    /// Builder class for configuring the account provider.
    ///
    /// This builder allows you to define how accounts are created.
    public class AccountProviderBuilder {
        private var registerAccount: ((_ loginId: String,
                                       _ profile: [String: Any],
                                       _ ownIdData: [String: Any]?,
                                       _ authToken: String?) async -> AuthResult)?
        
        /// Defines how accounts are created.
        ///
        /// Implement function to registers a new account with the given loginId and profile information.
        ///
        /// Set `ownIdData` to the user profile if available.
        /// - Parameter block: The closure to be executed upon completion. Closure parameters: **loginId** - The user's login identifier; **profile** - raw profile data received from the OwnID; **ownIdData** - optional data associated with the user; **authToken** - OwnID authentication token associated with the session (optional); returns ``OwnID/AuthResult`` with the result of the session creation operation.
        public func register(block: @escaping (_ loginId: String,
                                               _ profile: [String: Any],
                                               _ ownIdData: [String: Any]?,
                                               _ authToken: String?) async -> AuthResult) {
            registerAccount = block
        }
        
        /// Builds the ``AccountProviderProtocol`` instance.
        /// - Returns: The ``AccountProviderProtocol`` instance.
        func build() -> AccountProviderProtocol {
            return AccountProvider(registerAccount: registerAccount)
        }
        
        private class AccountProvider: AccountProviderProtocol {
            private let registerAccount: ((_ loginId: String,
                                           _ profile: [String: Any],
                                           _ ownIdData: [String: Any]?,
                                           _ authToken: String?) async -> AuthResult)?
            
            init(registerAccount: ((_ loginId: String,
                                    _ profile: [String: Any],
                                    _ ownIdData: [String: Any]?,
                                    _ authToken: String?) async -> AuthResult)?) {
                self.registerAccount = registerAccount
            }
            
            func register(loginId: String, profile: [String: Any], ownIdData: [String: Any]?, authToken: String?) async -> AuthResult {
                return await registerAccount?(loginId, profile, ownIdData, authToken) ?? .fail(reason: "Register block not provided")
            }
        }
    }
    
    /// Builder class for configuring the authentication providers.
    ///
    /// This builder allows you to define various authentication mechanisms.
    public class AuthProvidersBuilder {
        private var password: PasswordProviderProtocol?
        
        /// Configures the password authentication provider using a ``OwnID/PasswordProviderBuilder``.
        /// - Parameter block: A closure that configures the password authentication provider.
        public func password(block: (PasswordProviderBuilder) -> Void) {
            let builder = PasswordProviderBuilder()
            block(builder)
            password = builder.build()
        }
        
        /// Builds the ``AuthProviderProtocol`` instance.
        /// - Returns: The ``AuthProviderProtocol`` instance.
        func build() -> AuthProviderProtocol {
            if let password = password {
                return password
            } else {
                fatalError("No authentication method provided")
            }
        }
    }
    
    /// Builder class for configuring the password authentication provider.
    public class PasswordProviderBuilder {
        private var authenticate: ((_ loginId: String, _ password: String) async -> AuthResult)?
        
        /// Defines how password authentication is performed.
        ///
        /// Implement function to authenticates user with the given loginId and password.
        /// - Parameter block: The closure to be executed upon completion. Closure parameters: **loginId** - The user's login identifier;  **password** The user's password; returns ``OwnID/AuthResult`` with the result of the session creation operation.
        public func authenticate(block: @escaping (_ loginId: String, _ password: String) async -> AuthResult) {
            authenticate = block
        }
        
        /// Builds the ``PasswordProviderProtocol`` instance.
        /// - Returns: The ``PasswordProviderProtocol`` instance.
        func build() -> PasswordProviderProtocol {
            return PasswordProvider(authenticate: authenticate)
        }
        
        private class PasswordProvider: PasswordProviderProtocol {
            private let authenticate: ((_ loginId: String, _ password: String) async -> AuthResult)?
            
            init(authenticate: ((_ loginId: String, _ password: String) async -> AuthResult)?) {
                self.authenticate = authenticate
            }
            
            func authenticate(loginId: String, password: String) async -> AuthResult {
                return await authenticate?(loginId, password) ?? .fail(reason: "Authenticate block not provided")
            }
        }
    }
    
    /// Retrieves a logo for branding purposes.
    private class LogoProvider: LogoProviderProtocol {
        let logoClosure: (_ logoURL: URL?) -> AnyPublisher<Image?, Never>
        
        init(logoClosure: @escaping (_ logoURL: URL?) -> AnyPublisher<Image?, Never>) {
            self.logoClosure = logoClosure
        }
        
        /// Retrieves the logo image for the given URL.
        /// - Parameter logoURL: The URL where the logo is located.
        /// - Returns: A publisher that emits an optional `Image` corresponding to the logo at the URL,
        public func logo(logoURL: URL?) -> AnyPublisher<Image?, Never> {
            return logoClosure(logoURL)
        }
    }
}

extension OwnID {
    /// Configures global OwnID ``ProviderProtocol`` using an ``OwnID/ProvidersBuilder``.
    ///
    /// These providers will be used for all OwnID flows unless overridden using ``OwnID/start(_:)``.
    public static func providers(_ block: (ProvidersBuilder) -> Void) {
        let builder = ProvidersBuilder()
        block(builder)
        CoreSDK.providers = builder.build()
    }
}
