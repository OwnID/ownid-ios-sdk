import AuthenticationServices
import UIKit

@objc(OwnIDSignInWithAppleImpl)
internal final class SignInWithAppleImpl: NSObject, SignInWithApple, @unchecked Sendable {
    private let uiContextProvider: any UIContextProvider
    private let logger: OwnIDLogRouter?

    private var window: UIWindow?
    private var authController: ASAuthorizationController?
    private var continuation: CheckedContinuation<SocialResult, Never>?
    private var cancelRequested = false
    private var expectedState: String?

    init(uiContextProvider: any UIContextProvider, logger: OwnIDLogRouter?) {
        self.uiContextProvider = uiContextProvider
        self.logger = logger
    }

    @MainActor
    func signIn(params: SignInWithSocialParams) async -> SocialResult {
        let previousAuthController = authController
        authController = nil
        expectedState = nil

        if let existingContinuation = self.continuation {
            existingContinuation.resume(returning: .canceled(reason: .userClose(details: "Authorization restarted")))
            self.continuation = nil
        }

        cancelRequested = false

        if #available(iOS 16.0, *) {
            previousAuthController?.cancel()
        }

        self.window = params.window

        return await withCheckedContinuation { continuation in
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.email]
            request.nonce = params.nonce
            let requestState = Data.secureRandom(count: 32).encodeToBase64UrlSafe()
            request.state = requestState

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self

            self.authController = authorizationController
            self.continuation = continuation
            self.expectedState = requestState
            authorizationController.performRequests()
        }
    }

    @MainActor
    internal func cancel() {
        cancelRequested = true
        if #available(iOS 16.0, *) {
            authController?.cancel()
        }
    }
}

extension SignInWithAppleImpl: ASAuthorizationControllerDelegate {
    @MainActor
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === authController else { return }

        defer {
            continuation = nil
            authController = nil
            cancelRequested = false
            expectedState = nil
            window = nil
        }

        if cancelRequested {
            continuation?.resume(returning: .canceled(reason: .userClose(details: "Authorization canceled")))
            return
        }

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = appleIDCredential.identityToken
        else {
            continuation?.resume(returning: .fail(error: SocialResult.Error.general("Data missing")))
            return
        }

        guard appleIDCredential.state == expectedState else {
            continuation?.resume(returning: .fail(error: SocialResult.Error.general("Apple authorization response state mismatch")))
            return
        }

        continuation?.resume(
            returning: .success(
                id: appleIDCredential.user,
                idToken: String(decoding: identityTokenData, as: UTF8.self)
            )
        )
    }

    @MainActor
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === authController else { return }

        defer {
            continuation = nil
            authController = nil
            cancelRequested = false
            expectedState = nil
            window = nil
        }

        if cancelRequested {
            logger?.logI(source: self, prefix: "AppleSignIn", message: "Apple sign-in canceled", cause: error)
            continuation?.resume(returning: .canceled(reason: .userClose(details: "Authorization canceled")))
            return
        }

        guard let authorizationError = error as? ASAuthorizationError else {
            logger?.logW(source: self, prefix: "AppleSignIn", message: "Apple sign-in failed: \(error.localizedDescription)", cause: error)
            continuation?.resume(returning: .fail(error: SocialResult.Error.general("Error", error)))
            return
        }

        if authorizationError.code == .canceled {
            logger?.logI(
                source: self,
                prefix: "AppleSignIn",
                message: "Apple sign-in canceled: \(error.localizedDescription)",
                cause: error
            )
            continuation?.resume(returning: .canceled(reason: .userClose(details: "User canceled authorization")))
        } else {
            logger?.logW(source: self, prefix: "AppleSignIn", message: "Apple sign-in failed: \(error.localizedDescription)", cause: error)
            continuation?.resume(returning: .fail(error: SocialResult.Error.general("ASAuthorizationError", error)))
        }
    }
}

extension SignInWithAppleImpl: ASAuthorizationControllerPresentationContextProviding {
    @MainActor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window ?? uiContextProvider.activeWindow() ?? ASPresentationAnchor()
    }
}
