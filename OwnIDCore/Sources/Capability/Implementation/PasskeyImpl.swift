import AuthenticationServices
import Foundation

@available(iOS 16.0, *)
@MainActor
internal protocol PasskeyAuthorizationController: AnyObject {
    var authorizationRequests: [ASAuthorizationRequest] { get }
    var delegate: (any ASAuthorizationControllerDelegate)? { get set }
    var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)? { get set }

    func performRequests(options: ASAuthorizationController.RequestOptions)
    func cancel()
}

@available(iOS 16.0, *)
@MainActor
private final class ASAuthorizationControllerAdapter: PasskeyAuthorizationController {
    private let controller: ASAuthorizationController

    init(authorizationRequests: [ASAuthorizationRequest]) {
        self.controller = ASAuthorizationController(authorizationRequests: authorizationRequests)
    }

    var authorizationRequests: [ASAuthorizationRequest] {
        controller.authorizationRequests
    }

    var delegate: (any ASAuthorizationControllerDelegate)? {
        get { controller.delegate }
        set { controller.delegate = newValue }
    }

    var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)? {
        get { controller.presentationContextProvider }
        set { controller.presentationContextProvider = newValue }
    }

    func performRequests(options: ASAuthorizationController.RequestOptions) {
        controller.performRequests(options: options)
    }

    func cancel() {
        controller.cancel()
    }
}

@available(iOS 16.0, *)
@objc(OwnIDPasskeyImpl)
internal final class PasskeyImpl: NSObject, PasskeyProtocol, @unchecked Sendable {
    private static let immediateCanceledNoPasskeyThreshold: Duration = .milliseconds(600)

    private let uiContextProvider: any UIContextProvider
    private let logger: OwnIDLogRouter?
    private let diagnosticsProvider: () -> (any PasskeyDiagnostics)?
    private let now: @MainActor () -> ContinuousClock.Instant
    private let authorizationControllerFactory: @MainActor ([ASAuthorizationRequest]) -> any PasskeyAuthorizationController

    private var continuation: CheckedContinuation<PasskeyResult<any Sendable>, Never>?
    private var authController: (any PasskeyAuthorizationController)?
    private var currentContext: RequestContext?

    private struct RequestContext {
        enum Kind { case attestation, assertion }
        let kind: Kind
        let isImmediate: Bool
        let startedAt: ContinuousClock.Instant
    }

    init(
        uiContextProvider: any UIContextProvider,
        logger: OwnIDLogRouter?,
        diagnosticsProvider: @escaping () -> (any PasskeyDiagnostics)? = { nil },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now },
        authorizationControllerFactory: @escaping @MainActor ([ASAuthorizationRequest]) -> any PasskeyAuthorizationController =
            { ASAuthorizationControllerAdapter(authorizationRequests: $0) }
    ) {
        self.uiContextProvider = uiContextProvider
        self.logger = logger
        self.diagnosticsProvider = diagnosticsProvider
        self.now = now
        self.authorizationControllerFactory = authorizationControllerFactory
    }

    @MainActor
    func createCredential(attestationOptions: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        guard let challengeData = attestationOptions.challenge.value.decodeBase64UrlSafe() else {
            return .failure(.general("Failed to decode challenge data"))
        }

        let rpID = attestationOptions.rp.id
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        guard let userID = attestationOptions.user.id.decodeBase64UrlSafe() else {
            return .failure(.general("Failed to decode user ID"))
        }
        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: attestationOptions.user.name,
            userID: userID
        )

        switch attestationOptions.authenticatorSelection?.userVerification {
        case .discouraged: registrationRequest.userVerificationPreference = .discouraged
        case .preferred: registrationRequest.userVerificationPreference = .preferred
        case .required, nil: registrationRequest.userVerificationPreference = .required
        }
        if let attestation = attestationOptions.attestation {
            switch attestation {
            case .none: registrationRequest.attestationPreference = .none
            case .direct: registrationRequest.attestationPreference = .direct
            case .indirect: registrationRequest.attestationPreference = .indirect
            case .enterprise: registrationRequest.attestationPreference = .enterprise
            }
        }

        if #available(iOS 17.4, *) {
            registrationRequest.excludedCredentials = attestationOptions.excludeCredentials?.compactMap {
                guard let id = $0.id.decodeBase64UrlSafe() else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            }
        } else if !(attestationOptions.excludeCredentials?.isEmpty ?? true) {
            logger?.logI(source: self, prefix: #function, message: "setExcludedCredentials is not available on this iOS version")
        }

        let result = await performAuthorization(request: registrationRequest)
        switch result {
        case .success(let value as AttestationResult):
            return .success(value)
        case .canceled(let reason):
            return .canceled(reason)
        case .failure(let error):
            diagnosticsProvider()?.verify(rpId: rpID)
            return .failure(mapPasskeyError(error))
        default:
            diagnosticsProvider()?.verify(rpId: rpID)
            return .failure(.general("Unexpected result type from authorization (Attestation)"))
        }
    }

    @MainActor
    func getCredential(assertionOptions: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        guard let challengeData = assertionOptions.challenge.value.decodeBase64UrlSafe() else {
            return .failure(.general("Failed to decode challenge data"))
        }

        let rpID = assertionOptions.rpID
        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challengeData)
        if let userVerification = assertionOptions.userVerification {
            switch userVerification {
            case .discouraged: assertionRequest.userVerificationPreference = .discouraged
            case .preferred: assertionRequest.userVerificationPreference = .preferred
            case .required: assertionRequest.userVerificationPreference = .required
            }
        }

        if let allowedList = assertionOptions.allowCredentials {
            let allowed: [ASAuthorizationPlatformPublicKeyCredentialDescriptor] = allowedList.compactMap {
                cred -> ASAuthorizationPlatformPublicKeyCredentialDescriptor? in
                guard let id = cred.id.decodeBase64UrlSafe() else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            }
            if !allowed.isEmpty {
                assertionRequest.allowedCredentials = allowed
            }
        }

        let result = await performAuthorization(request: assertionRequest, options: [.preferImmediatelyAvailableCredentials])
        switch result {
        case .success(let value as AssertionResult):
            return .success(value)
        case .canceled(let reason):
            return .canceled(reason)
        case .failure(let error):
            switch error {
            case .general:
                diagnosticsProvider()?.verify(rpId: rpID)
            case .passkeysNoCredential:
                break
            }
            return .failure(mapPasskeyError(error))
        default:
            diagnosticsProvider()?.verify(rpId: rpID)
            return .failure(.general("Unexpected result type from authorization (Assertion)"))
        }
    }

    @MainActor
    private func performAuthorization(
        request: ASAuthorizationRequest,
        options: ASAuthorizationController.RequestOptions = []
    ) async -> PasskeyResult<any Sendable> {
        guard continuation == nil else {
            return .failure(.general("Another passkey request is already in progress"))
        }

        let authController = authorizationControllerFactory([request])
        let controllerWrapper = UnsafeSendableWrapper(value: authController)
        self.authController = authController

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                authController.delegate = self
                authController.presentationContextProvider = self

                let kind: RequestContext.Kind =
                    (request is ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest) ? .attestation : .assertion
                let isImmediate = options.contains(.preferImmediatelyAvailableCredentials)
                self.currentContext = RequestContext(
                    kind: kind,
                    isImmediate: isImmediate,
                    startedAt: now()
                )
                authController.performRequests(options: options)
            }
        } onCancel: {
            Task { @MainActor in controllerWrapper.value.cancel() }
        }
    }

    @MainActor
    private func resumeContinuation(with result: PasskeyResult<any Sendable>) {
        continuation?.resume(returning: result)
        continuation = nil
        authController = nil
        currentContext = nil
    }
}

@available(iOS 16.0, *)
extension PasskeyImpl: ASAuthorizationControllerDelegate {
    @MainActor
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let credential as ASAuthorizationPlatformPublicKeyCredentialRegistration: handleAttestationSuccess(credential: credential)
        case let credential as ASAuthorizationPlatformPublicKeyCredentialAssertion: handleAssertionSuccess(credential: credential)
        default: resumeContinuation(with: .failure(.general("Unknown or mismatched credential type received")))
        }
    }

    @MainActor
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let logPrefix =
            (controller.authorizationRequests.first is ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest)
            ? "createCredential" : "getCredential"

        let identifier = authorizationErrorIdentifier(from: error)
        let result: PasskeyResult<any Sendable>
        if let authError = error as? ASAuthorizationError {
            if authError.code == .canceled, let ctx = currentContext, ctx.kind == .assertion, ctx.isImmediate {
                let elapsed = now() - ctx.startedAt
                if elapsed < Self.immediateCanceledNoPasskeyThreshold {
                    logger?.logI(source: self, prefix: logPrefix, message: "No credential available", cause: error)
                    result = .failure(.passkeysNoCredential("No Credentials Available", authError, .noCredential))
                } else {
                    logger?.logI(source: self, prefix: logPrefix, message: "Authorization canceled", cause: error)
                    result = .canceled(.userClose(details: "User canceled authorization"))
                }
            } else if authError.code == .canceled {
                logger?.logI(source: self, prefix: logPrefix, message: "Authorization canceled", cause: error)
                result = .canceled(.userClose(details: "User canceled authorization"))
            } else {
                logger?.logW(source: self, prefix: logPrefix, message: "Authorization failed", cause: error)
                result = .failure(.general(error.localizedDescription, error, identifier))
            }
        } else {
            logger?.logW(source: self, prefix: logPrefix, message: "Authorization failed", cause: error)
            result = .failure(.general(error.localizedDescription, error, identifier))
        }
        resumeContinuation(with: result)
    }

    @MainActor
    private func handleAttestationSuccess(credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) {
        guard let attestationObject = credential.rawAttestationObject?.encodeToBase64UrlSafe() else {
            resumeContinuation(with: .failure(.general("Attestation object is missing")))
            return
        }

        let response = AttestationResult.AuthenticatorResponse(
            clientDataJSON: credential.rawClientDataJSON.encodeToBase64UrlSafe(),
            attestationObject: attestationObject,
            transports: [.internal, .hybrid]
        )

        let attachment: AuthenticatorAttachment?
        if #available(iOS 16.6, *) {
            switch credential.attachment {
            case .platform: attachment = .platform
            case .crossPlatform: attachment = .crossPlatform
            @unknown default: attachment = nil
            }
        } else {
            attachment = nil
        }

        let attestationResult = AttestationResult(
            id: credential.credentialID.encodeToBase64UrlSafe(),
            type: .publicKey,
            response: response,
            authenticatorAttachment: attachment
        )
        resumeContinuation(with: .success(attestationResult))
    }

    @MainActor
    private func handleAssertionSuccess(credential: ASAuthorizationPlatformPublicKeyCredentialAssertion) {
        let response = AssertionResult.AuthenticatorResponse(
            clientDataJSON: credential.rawClientDataJSON.encodeToBase64UrlSafe(),
            authenticatorData: credential.rawAuthenticatorData.encodeToBase64UrlSafe(),
            signature: credential.signature.encodeToBase64UrlSafe(),
            userHandle: credential.userID?.encodeToBase64UrlSafe()
        )

        let attachment: AuthenticatorAttachment
        if #available(iOS 16.6, *) {
            switch credential.attachment {
            case .platform: attachment = .platform
            case .crossPlatform: attachment = .crossPlatform
            @unknown default: attachment = .platform
            }
        } else {
            attachment = .platform
        }

        let assertionResult = AssertionResult(
            id: credential.credentialID.encodeToBase64UrlSafe(),
            type: .publicKey,
            response: response,
            authenticatorAttachment: attachment
        )
        resumeContinuation(with: .success(assertionResult))
    }

    private struct UnsafeSendableWrapper<T>: @unchecked Sendable {
        let value: T
    }

    private func mapPasskeyError<R>(_ error: PasskeyResult<any Sendable>.Error) -> PasskeyResult<R>.Error {
        switch error {
        case .general(let message, let cause, let identifier): return .general(message, cause, identifier)
        case .passkeysNoCredential(let message, let cause, let identifier): return .passkeysNoCredential(message, cause, identifier)
        }
    }

    private func authorizationErrorIdentifier(from error: any Error) -> PasskeyAuthorizationErrorIdentifier? {
        if let authError = error as? ASAuthorizationError {
            return PasskeyAuthorizationErrorIdentifier.fromAuthorizationErrorCode(authError.code.rawValue)
        }

        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationErrorDomain else { return nil }
        return PasskeyAuthorizationErrorIdentifier.fromAuthorizationErrorCode(nsError.code)
    }
}

@available(iOS 16.0, *)
extension PasskeyImpl: ASAuthorizationControllerPresentationContextProviding {
    @MainActor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        uiContextProvider.activeWindow() ?? ASPresentationAnchor()
    }
}
