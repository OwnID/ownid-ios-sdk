import Foundation

/// OwnID namespace for direct server API access.
///
/// Use this namespace when you want to call individual OwnID server APIs yourself instead of running a higher-level
/// operation or flow. Direct API entries make one API request and return ``APIResult``; operation lifecycle, UI, and
/// settlement controllers belong to ``OwnIDOperation`` instead.
///
/// Namespace handles are bound to the SDK scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned namespace handles are
/// invalid and should be reacquired from the current ``OwnIDInstance``.
///
/// Use ``withContext(_:_:)`` to scope calls with a login ID or access token, or ``withProviders(_:_:)`` to register
/// scoped providers, then call the selected API through ``APIEntry/start(params:)``.
/// Entries whose parameter type is optional support the zero-argument `start()` overload; enrollment entries require
/// explicit params.
///
/// Entries resolve their runtime from the bound scope when ``APIEntry/start(params:)`` is called. See ``APIEntry`` for
/// missing-dependency and cancellation behavior.
public struct OwnIDAPI: Sendable, OwnIDNamespace {
    internal let container: any DIContainer

    public let auth: Auth

    public let passkeys: Passkeys

    public let verifications: Verifications

    public let enroll: Enroll

    /// OpenID Connect API.
    public let oidc: APIEntry<OIDCAPIParams?, any OIDCAPIController, OIDCStartAPIFailure>

    internal init(container: any DIContainer) {
        self.container = container
        self.auth = Auth(container: container)
        self.passkeys = Passkeys(container: container)
        self.verifications = Verifications(container: container)
        self.enroll = Enroll(container: container)
        self.oidc = apiEntry(
            container: container,
            runtimeType: (any OIDCAPI).self,
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
                start: { runtime, params in
                    await runtime.start(params: params)
                }
            )
            self.login = apiEntry(
                container: container,
                runtimeType: (any LoginAPI).self,
                start: { runtime, params in
                    await runtime.start(params: params)
                }
            )
        }
    }

    /// Passkey API group.
    ///
    /// Use these APIs to start passkey attestation or assertion directly.
    public struct Passkeys: Sendable {
        /// Starts passkey creation.
        public let attestation:
            APIEntry<PasskeyAttestationAPIParams?, any PasskeyAttestationAPIController, PasskeyAttestationStartAPIFailure>

        /// Starts passkey authentication.
        public let assertion: APIEntry<PasskeyAssertionAPIParams?, any PasskeyAssertionAPIController, PasskeyAssertionStartAPIFailure>

        fileprivate init(container: any DIContainer) {
            self.attestation = apiEntry(
                container: container,
                runtimeType: (any PasskeyAttestationAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
            self.assertion = apiEntry(
                container: container,
                runtimeType: (any PasskeyAssertionAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
        }
    }

    /// Verification APIs.
    ///
    /// Each API starts a verification challenge and returns a controller for code entry, resend, and cancellation.
    public struct Verifications: Sendable {
        /// Starts email verification.
        public let email: APIEntry<EmailVerificationAPIParams?, any EmailVerificationAPIController, EmailVerificationStartAPIFailure>

        /// Starts phone verification.
        public let phone: APIEntry<PhoneVerificationAPIParams?, any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>

        fileprivate init(container: any DIContainer) {
            self.email = apiEntry(
                container: container,
                runtimeType: (any EmailVerificationAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
            self.phone = apiEntry(
                container: container,
                runtimeType: (any PhoneVerificationAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
        }
    }

    /// Credential enrollment API group.
    ///
    /// Each API enrolls one credential type using the token produced by the matching earlier verification or
    /// attestation step.
    public struct Enroll: Sendable {
        /// Enrolls a passkey with a proof token.
        public let passkey: APIEntry<PasskeyEnrollAPIParams, Void, PasskeyEnrollAPIFailure>

        /// Enrolls an email address with a proof token.
        public let email: APIEntry<EmailEnrollAPIParams, Void, EmailEnrollAPIFailure>

        /// Enrolls a phone number with a proof token.
        public let phone: APIEntry<PhoneEnrollAPIParams, Void, PhoneEnrollAPIFailure>

        fileprivate init(container: any DIContainer) {
            self.passkey = apiEntry(
                container: container,
                runtimeType: (any PasskeyEnrollAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
            self.email = apiEntry(
                container: container,
                runtimeType: (any EmailEnrollAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
            self.phone = apiEntry(
                container: container,
                runtimeType: (any PhoneEnrollAPI).self,
                start: { runtime, params in await runtime.start(params: params) }
            )
        }
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var apiNamespace: OwnIDAPI {
        OwnIDAPI(container: self)
    }
}
