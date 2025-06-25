import AuthenticationServices
import os

extension OwnID.CoreSDK {
    class AuthManager: NSObject {
        let authenticationAnchor = ASPresentationAnchor()

        private let store: Store<OwnID.CoreSDK.AuthManager.State, OwnID.CoreSDK.AuthManager.Action>
        private let domain: String
        private let challenge: String

        private var challengeData: Data {
            challenge.data(using: .utf8)!
        }

        private var currentAuthController: ASAuthorizationController?
        private var isPerformingModalReqest = false

        init(
            store: Store<OwnID.CoreSDK.AuthManager.State, OwnID.CoreSDK.AuthManager.Action>,
            domain: String,
            challenge: String
        ) {
            self.store = store
            self.domain = domain
            self.challenge = challenge
        }

        @available(iOS 16.0, *)
        func signIn(credsIds: [String]) {
            currentAuthController?.cancel()
            let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)
            let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challengeData)

            let creds =
                credsIds
                .compactMap { Data(base64urlEncoded: $0) }
                .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
            assertionRequest.allowedCredentials = creds

            let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests(options: [.preferImmediatelyAvailableCredentials])
            currentAuthController = authController
            isPerformingModalReqest = true
        }

        @available(iOS 16.0, *)
        func signUpWith(
            userName: String,
            userID: String? = nil,
            credsIds: [String]
        ) {
            currentAuthController?.cancel()

            let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)

            let userID = userID?.data(using: .utf8) ?? Data.generateRandomBytes()
            let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(
                challenge: challengeData,
                name: userName,
                userID: userID
            )
            let creds =
                credsIds
                .compactMap { Data(base64urlEncoded: $0) }
                .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }

            registrationRequest.userVerificationPreference = .required

            if #available(iOS 17.4, *) {
                registrationRequest.excludedCredentials = creds
            } else {
                OwnID.CoreSDK.logger.log(level: .warning, message: "setExcludedCredentials isn't available", type: Self.self)
            }

            let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests()
            currentAuthController = authController
            isPerformingModalReqest = true
        }

        @available(iOS 16.0, *)
        func cancel() {
            currentAuthController?.cancel()
        }

        deinit {
            if #available(iOS 16.0, *) {
                cancel()
            }
        }
    }
}

@available(iOS 16.0, *)
extension OwnID.CoreSDK.AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        switch authorization.credential {
        case let credentialRegistration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            guard let attestationObject = credentialRegistration.rawAttestationObject?.base64urlEncodedString()
            else {
                store.send(.error(error: .authManagerDataMissing, context: challenge))
                return
            }

            let clientDataJSON = credentialRegistration.rawClientDataJSON.base64urlEncodedString()
            let credentialID = credentialRegistration.credentialID.base64urlEncodedString()

            let payload = OwnID.CoreSDK.Fido2RegisterPayload(
                credentialId: credentialID,
                clientDataJSON: clientDataJSON,
                attestationObject: attestationObject
            )
            store.send(.didFinishRegistration(fido2RegisterPayload: payload))

        case let credentialAssertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            let signature = credentialAssertion.signature.base64urlEncodedString()
            let rawAuthenticatorData = credentialAssertion.rawAuthenticatorData.base64urlEncodedString()
            let clientDataJSON = credentialAssertion.rawClientDataJSON
            let credentialID = credentialAssertion.credentialID.base64urlEncodedString()

            let payload = OwnID.CoreSDK.Fido2LoginPayload(
                credentialId: credentialID,
                clientDataJSON: clientDataJSON.base64urlEncodedString(),
                authenticatorData: rawAuthenticatorData,
                signature: signature
            )
            store.send(.didFinishLogin(fido2LoginPayload: payload))

        default:
            store.send(.error(error: .authManagerUnknownAuthType, context: challenge))
        }

        isPerformingModalReqest = false
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Swift.Error) {
        defer {
            OwnID.CoreSDK.logger.log(
                level: .warning,
                message: "FIDO: \(error.localizedDescription)",
                errorMessage: error.localizedDescription,
                type: Self.self
            )
            currentAuthController?.cancel()
            controller.cancel()
        }
        guard let authorizationError = error as? ASAuthorizationError else {
            isPerformingModalReqest = false
            store.send(.error(error: .authManagerGeneralError(underlying: error), context: challenge))
            return
        }

        if authorizationError.code == .canceled {
            if isPerformingModalReqest {
                if authorizationError.userInfo["NSLocalizedFailureReason"] is String {
                    store.send(.error(error: .authManagerCredintialsNotFound(underlying: authorizationError), context: challenge))
                } else {
                    store.send(.error(error: .authManagerCanlelledByUser(underlying: authorizationError), context: challenge))
                }
            }
        } else {
            store.send(.error(error: .authManagerAuthError(underlying: error), context: challenge))
        }

        isPerformingModalReqest = false
    }
}

@available(iOS 16.0, *)
extension OwnID.CoreSDK.AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        authenticationAnchor
    }
}

extension OwnID.CoreSDK.AuthManager {
    struct State {
    }

    enum Action {
        case didFinishRegistration(fido2RegisterPayload: OwnID.CoreSDK.Fido2RegisterPayload)
        case didFinishLogin(fido2LoginPayload: OwnID.CoreSDK.Fido2LoginPayload)
        case error(error: AuthManagerError, context: OwnID.CoreSDK.Context)
    }

    enum AuthManagerError: Error {
        case authManagerGeneralError(underlying: Swift.Error)
        case authManagerCanlelledByUser(underlying: ASAuthorizationError)
        case authManagerCredintialsNotFound(underlying: ASAuthorizationError)
        case authManagerAuthError(underlying: Swift.Error)
        case authManagerDataMissing
        case authManagerUnknownAuthType

        public var errorDescription: String {
            return "Error while performing action"
        }
    }
}

extension OwnID.CoreSDK.AuthManager.Action: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .didFinishRegistration:
            return "didFinishRegistration"

        case .didFinishLogin:
            return "didFinishLogin"

        case .error:
            return "generalError"
        }
    }
}
