import Foundation

/// OwnID namespace for direct server API access.
///
/// Use this namespace when you want to call individual OwnID server APIs yourself instead of running a higher-level
/// operation or flow. Direct API entries make one API request and return ``APIResult``; operation lifecycle, UI, and
/// settlement controllers belong to ``OwnIDOperation`` instead.
///
/// Namespace handles remain associated with the SDK instance state from which they were obtained.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned namespace handles are
/// invalid and should be reacquired from the current ``OwnIDInstance``.
///
/// Use ``withContext(_:_:)`` to scope calls with a login ID or access token, or ``withProviders(_:_:)`` to register
/// scoped providers, then call the selected API through ``APIEntry/start(params:)``.
/// Entries whose parameter type is optional support the zero-argument `start()` overload; enrollment entries require
/// explicit params.
///
/// Each ``APIEntry/start(params:)`` call returns the endpoint-specific result. Surrounding-task cancellation before
/// completion returns ``APIResult/canceled``. If the SDK cannot prepare the selected API for another reason, the result
/// contains that endpoint's `unexpected` failure.
public struct OwnIDAPI: Sendable, OwnIDNamespace {
    internal let container: any DIContainer

    public let auth: Auth

    public let passkeys: Passkeys

    public let verifications: Verifications

    /// OpenID Connect API.
    public let oidc: APIEntry<OIDCAPIParams?, any OIDCAPIController, OIDCStartAPIFailure>

    internal init(container: any DIContainer) {
        self.container = container
        self.auth = Auth(container: container)
        self.passkeys = Passkeys(container: container)
        self.verifications = Verifications(container: container)
        self.oidc = apiEntry(
            container: container,
            runtimeType: (any OIDCAPI).self,
            unexpectedFailure: OIDCStartAPIFailure.unexpected,
            start: { runtime, params in
                await runtime.start(params: params)
            }
        )
    }
}

extension OwnIDAPI: OwnIDNamespaceSupport {}

extension OwnIDAPI {
    internal func rebind(container: any DIContainer) -> OwnIDAPI {
        OwnIDAPI(container: container)
    }
}

extension OwnIDAPI {
    /// Authentication API group.
    ///
    /// Use ``discover`` to start from a login ID, or ``login`` to continue with an access token.
    public struct Auth: Sendable {
        /// Looks up authentication requirements for a login ID.
        public let discover: APIEntry<DiscoverAPIParams?, LoginResponse, DiscoverAPIFailure>

        /// Authenticates a proven login using an access token and returns the login response/session payload.
        public let login: APIEntry<LoginAPIParams?, LoginResponse, LoginAPIFailure>

        fileprivate init(container: any DIContainer) {
            self.discover = apiEntry(
                container: container,
                runtimeType: (any DiscoverAPI).self,
                unexpectedFailure: DiscoverAPIFailure.unexpected,
                start: { runtime, params in
                    await runtime.start(params: params)
                }
            )
            self.login = apiEntry(
                container: container,
                runtimeType: (any LoginAPI).self,
                unexpectedFailure: LoginAPIFailure.unexpected,
                start: { runtime, params in
                    await runtime.start(params: params)
                }
            )
        }
    }

    /// Passkey API group.
    ///
    /// Use these APIs to start passkey attestation or assertion directly, or enroll a proven passkey.
    public struct Passkeys: Sendable {
        /// Starts passkey creation.
        public let attestation:
            APIEntry<PasskeyAttestationAPIParams?, any PasskeyAttestationAPIController, PasskeyAttestationStartAPIFailure>

        /// Starts passkey authentication.
        public let assertion: APIEntry<PasskeyAssertionAPIParams?, any PasskeyAssertionAPIController, PasskeyAssertionStartAPIFailure>

        /// Enrolls a passkey with a proof token.
        public let enroll: APIEntry<PasskeyEnrollAPIParams, Void, PasskeyEnrollAPIFailure>

        fileprivate init(container: any DIContainer) {
            self.attestation = apiEntry(
                container: container,
                runtimeType: (any PasskeyAttestationAPI).self,
                unexpectedFailure: PasskeyAttestationStartAPIFailure.unexpected,
                start: { runtime, params in await runtime.start(params: params) }
            )
            self.assertion = apiEntry(
                container: container,
                runtimeType: (any PasskeyAssertionAPI).self,
                unexpectedFailure: PasskeyAssertionStartAPIFailure.unexpected,
                start: { runtime, params in await runtime.start(params: params) }
            )
            self.enroll = apiEntry(
                container: container,
                runtimeType: (any PasskeyEnrollAPI).self,
                unexpectedFailure: PasskeyEnrollAPIFailure.unexpected,
                start: { runtime, params in await runtime.start(params: params) }
            )
        }
    }

    /// Verification and enrollment APIs.
    ///
    /// Each channel starts a verification challenge and returns a controller for code entry, resend, and cancellation.
    /// Enrollment uses the proof token produced by the matching earlier proof step.
    public struct Verifications: Sendable {
        /// Email verification and enrollment APIs.
        public let email: Email

        /// Phone verification and enrollment APIs.
        public let phone: Phone

        fileprivate init(container: any DIContainer) {
            self.email = Email(container: container)
            self.phone = Phone(container: container)
        }

        public struct Email: Sendable {
            private let verification:
                APIEntry<EmailVerificationAPIParams?, any EmailVerificationAPIController, EmailVerificationStartAPIFailure>

            /// Enrolls an email address with a proof token.
            public let enroll: APIEntry<EmailEnrollAPIParams, Void, EmailEnrollAPIFailure>

            fileprivate init(container: any DIContainer) {
                self.verification = apiEntry(
                    container: container,
                    runtimeType: (any EmailVerificationAPI).self,
                    unexpectedFailure: EmailVerificationStartAPIFailure.unexpected,
                    start: { runtime, params in await runtime.start(params: params) }
                )
                self.enroll = apiEntry(
                    container: container,
                    runtimeType: (any EmailEnrollAPI).self,
                    unexpectedFailure: EmailEnrollAPIFailure.unexpected,
                    start: { runtime, params in await runtime.start(params: params) }
                )
            }

            /// Starts email verification using the current context.
            public func start() async -> APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure> {
                await verification.start()
            }

            /// Starts email verification with optional request parameters.
            public func start(params: EmailVerificationAPIParams?) async
                -> APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure>
            {
                await verification.start(params: params)
            }
        }

        public struct Phone: Sendable {
            private let verification:
                APIEntry<PhoneVerificationAPIParams?, any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>

            /// Enrolls a phone number with a proof token.
            public let enroll: APIEntry<PhoneEnrollAPIParams, Void, PhoneEnrollAPIFailure>

            fileprivate init(container: any DIContainer) {
                self.verification = apiEntry(
                    container: container,
                    runtimeType: (any PhoneVerificationAPI).self,
                    unexpectedFailure: PhoneVerificationStartAPIFailure.unexpected,
                    start: { runtime, params in await runtime.start(params: params) }
                )
                self.enroll = apiEntry(
                    container: container,
                    runtimeType: (any PhoneEnrollAPI).self,
                    unexpectedFailure: PhoneEnrollAPIFailure.unexpected,
                    start: { runtime, params in await runtime.start(params: params) }
                )
            }

            /// Starts phone verification using the current context.
            public func start() async -> APIResult<any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure> {
                await verification.start()
            }

            /// Starts phone verification with optional request parameters.
            public func start(params: PhoneVerificationAPIParams?) async
                -> APIResult<any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>
            {
                await verification.start(params: params)
            }
        }
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var apiNamespace: OwnIDAPI {
        OwnIDAPI(container: self)
    }
}
