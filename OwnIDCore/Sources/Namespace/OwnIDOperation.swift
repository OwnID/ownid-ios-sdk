import Foundation

/// OwnID operation namespace.
///
/// Use this namespace when you want to launch one authentication step directly instead of running a composite flow or a
/// raw server API call. Operation entries run SDK operation lifecycles and return caller-owned controllers; direct
/// server API calls belong to ``OwnIDAPI`` instead.
///
/// Namespace handles are bound views of the SDK instance and context/provider scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned namespace handles are
/// invalid and should be reacquired from the current ``OwnIDInstance``.
///
/// Use ``withContext(_:_:)`` to scope operations with a login ID or access token and ``withProviders(_:_:)`` to
/// register providers. Use ``OperationEntry/start(params:)`` to launch the selected operation. Check
/// ``OperationEntry/availability(params:)`` or ``OperationEntry/isAvailable(params:)`` before starting when the app
/// needs to know whether required providers, UI, passkey support, or inputs are currently available. Entries whose
/// parameter type is optional support zero-argument availability and start overloads; passkey enrollment requires
/// explicit params.
///
/// Each ``OperationEntry/start(params:)`` call starts a separate operation lifecycle and returns a caller-owned
/// controller for settlement and cancellation. Availability checks and starts use that bound scope at the time they are
/// called. See ``OperationEntry`` for preflight and missing-dependency behavior.
public struct OwnIDOperation: Sendable, OwnIDNamespace {
    internal let container: any DIContainer

    public let loginID: LoginID

    public let verifications: Verifications

    public let passkeys: Passkeys

    public let socialLogin: SocialLogin

    /// Starts token-first authentication and returns a ``LoginResponse``.
    public let login: any OperationEntry<LoginOperationParams?, LoginResponse, LoginOperationFailure>

    internal init(container: any DIContainer) {
        self.container = container
        self.loginID = LoginID(container: container)
        self.verifications = Verifications(container: container)
        self.passkeys = Passkeys(container: container)
        self.socialLogin = SocialLogin(container: container)
        self.login = operationEntry(
            container: container,
            runtimeType: (any LoginOperation).self,
            operationType: .sessionCreation,
            availability: { runtime, params in await runtime.availability(params: params) },
            start: { runtime, params in runtime.start(params: params) }
        )
    }
}

extension OwnIDOperation: OwnIDNamespaceSupport {}

extension OwnIDOperation {
    internal func rebind(container: any DIContainer) -> OwnIDOperation {
        OwnIDOperation(container: container)
    }
}

extension OwnIDOperation {
    public struct LoginID: Sendable {
        /// Collects a login ID.
        public let collect: any OperationEntry<LoginIDCollectOperationParams?, OwnIDCore.LoginID, LoginIDCollectOperationFailure>

        fileprivate init(container: any DIContainer) {
            self.collect = scopedOperationEntry(
                container: container,
                runtimeType: (any LoginIDCollectOperation).self,
                operationType: .loginIDCollect,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
        }
    }

    public struct Verifications: Sendable {
        /// Verifies an email address.
        public let email: any OperationEntry<EmailVerificationOperationParams?, AccessOrProofToken, EmailVerificationOperationFailure>

        /// Verifies a phone number.
        public let phone: any OperationEntry<PhoneVerificationOperationParams?, AccessOrProofToken, PhoneVerificationOperationFailure>

        fileprivate init(container: any DIContainer) {
            self.email = scopedOperationEntry(
                container: container,
                runtimeType: (any EmailVerificationOperation).self,
                operationType: .emailVerification,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
            self.phone = scopedOperationEntry(
                container: container,
                runtimeType: (any PhoneVerificationOperation).self,
                operationType: .phoneNumberVerification,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
        }
    }

    /// Passkey operation group.
    ///
    /// Use ``create`` to register a passkey, ``auth`` to authenticate with an existing passkey, and ``enroll`` to
    /// complete passkey enrollment from a proof token.
    public struct Passkeys: Sendable {
        /// Starts passkey creation.
        public let create: any OperationEntry<PasskeyAttestationOperationParams?, AttestationResponse, PasskeyAttestationOperationFailure>

        /// Starts passkey authentication.
        public let auth: any OperationEntry<PasskeyAssertionOperationParams?, AccessToken, PasskeyAssertionOperationFailure>

        /// Enrolls a passkey with a proof token.
        public let enroll: any OperationEntry<PasskeyEnrollOperationParams, Void, PasskeyEnrollOperationFailure>

        fileprivate init(container: any DIContainer) {
            self.create = operationEntry(
                container: container,
                runtimeType: (any PasskeyAttestationOperation).self,
                operationType: .passkeyCreation,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
            self.auth = operationEntry(
                container: container,
                runtimeType: (any PasskeyAssertionOperation).self,
                operationType: .passkeyAuth,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
            self.enroll = operationEntry(
                container: container,
                runtimeType: (any PasskeyEnrollOperation).self,
                operationType: .passkeyEnrollment,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
        }
    }

    /// Social login operation group.
    public struct SocialLogin: Sendable {
        /// Starts Sign in with Apple.
        public let signInWithApple:
            any OperationEntry<SignInWithAppleOperationParams?, AccessTokenWithUserInfo, SignInWithAppleOperationFailure>

        /// Starts Sign in with Google.
        public let signInWithGoogle:
            any OperationEntry<SignInWithGoogleOperationParams?, AccessTokenWithUserInfo, SignInWithGoogleOperationFailure>

        fileprivate init(container: any DIContainer) {
            self.signInWithApple = operationEntry(
                container: container,
                runtimeType: (any SignInWithAppleOperation).self,
                operationType: .oidcAuthenticationApple,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
            self.signInWithGoogle = operationEntry(
                container: container,
                runtimeType: (any SignInWithGoogleOperation).self,
                operationType: .oidcAuthenticationGoogle,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
        }
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var opsNamespace: OwnIDOperation {
        OwnIDOperation(container: self)
    }
}
