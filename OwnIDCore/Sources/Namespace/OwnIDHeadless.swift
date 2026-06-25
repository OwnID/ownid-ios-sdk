import Foundation

/// UI-less OwnID authentication namespace.
///
/// Use this namespace when you want direct OwnID APIs, operations, and the passkey enrollment flow without starting
/// from the higher-level flow namespace.
///
/// Namespace handles are bound to the SDK scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned namespace handles are
/// invalid and should be reacquired from ``OwnID/headless`` or the current ``OwnIDInstance``.
///
/// Scope it with ``withContext(_:_:)`` or ``withProviders(_:_:)``, then launch the selected API, operation, or flow.
/// Optional parameter and context types support zero-argument start/preflight overloads; the selected entry decides
/// whether omitted values are valid and how the current ``Context`` is used.
/// Direct API entries return ``APIResult`` for success, handled failures, and task cancellation.
/// Operation and flow entries return caller-owned controllers that should be observed until settlement.
/// Namespace entry properties do not resolve their underlying runtime until start or preflight availability is called.
///
/// Accessed via ``OwnID/headless`` (default instance) or ``OwnIDInstance/headless``.
public struct OwnIDHeadless: Sendable, OwnIDNamespace {
    internal let container: any DIContainer

    public let auth: Auth

    public let passkeys: Passkeys

    public let verifications: Verifications

    internal init(container: any DIContainer) {
        self.container = container
        self.auth = Auth(container: container)
        self.passkeys = Passkeys(container: container)
        self.verifications = Verifications(container: container)
    }
}

extension OwnIDHeadless: OwnIDNamespaceSupport {}

extension OwnIDHeadless {
    internal func rebind(container: any DIContainer) -> OwnIDHeadless {
        OwnIDHeadless(container: container)
    }
}

extension OwnIDHeadless {
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

    /// Passkey operation group.
    ///
    /// Use ``auth`` to authenticate with a passkey, ``create`` to register one, and ``enroll`` to run the full
    /// passkey enrollment flow.
    public struct Passkeys: Sendable {
        /// Starts passkey authentication.
        public let auth: any OperationEntry<PasskeyAssertionOperationParams?, AccessToken, PasskeyAssertionOperationFailure>

        /// Starts passkey creation.
        public let create: any OperationEntry<PasskeyAttestationOperationParams?, AttestationResponse, PasskeyAttestationOperationFailure>

        /// Passkey enrollment flow that uses an access token, runs passkey attestation when no proof token is provided,
        /// and completes server enrollment.
        public let enroll: PreflightFlowEntry<PasskeyEnrollFlowContext?, any PasskeyEnrollController>

        fileprivate init(container: any DIContainer) {
            self.auth = operationEntry(
                container: container,
                runtimeType: (any PasskeyAssertionOperation).self,
                operationType: .passkeyAuth,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
            self.create = operationEntry(
                container: container,
                runtimeType: (any PasskeyAttestationOperation).self,
                operationType: .passkeyCreation,
                availability: { runtime, params in await runtime.availability(params: params) },
                start: { runtime, params in runtime.start(params: params) }
            )
            self.enroll = preflightFlowEntry(
                container: container,
                runtimeType: (any PasskeyEnrollFlow).self,
                availability: { runtime, context in await runtime.availability(params: context) },
                start: { runtime, context in runtime.start(context) }
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
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var headlessNamespace: OwnIDHeadless {
        OwnIDHeadless(container: self)
    }
}
