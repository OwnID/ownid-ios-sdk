import AuthenticationServices
import UIKit

internal struct SignInWithAppleAuthorization: Sendable {
    let user: String
    let state: String?
    let identityToken: Data?
}

@MainActor
internal protocol SignInWithAppleAuthorizationControllerDelegate: AnyObject {
    func authorizationController(
        _ controller: any SignInWithAppleAuthorizationController,
        didCompleteWithAuthorization authorization: SignInWithAppleAuthorization?
    )
    func authorizationController(
        _ controller: any SignInWithAppleAuthorizationController,
        didCompleteWithError error: any Error
    )
}

@MainActor
internal protocol SignInWithAppleAuthorizationController: AnyObject {
    var delegate: (any SignInWithAppleAuthorizationControllerDelegate)? { get set }
    var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)? { get set }

    func performRequests()
    func cancel()
}

@MainActor
private final class ASAuthorizationControllerAdapter: NSObject, SignInWithAppleAuthorizationController, ASAuthorizationControllerDelegate {
    private let controller: ASAuthorizationController

    init(request: ASAuthorizationAppleIDRequest) {
        controller = ASAuthorizationController(authorizationRequests: [request])
    }

    weak var delegate: (any SignInWithAppleAuthorizationControllerDelegate)?

    var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)? {
        get { controller.presentationContextProvider }
        set { controller.presentationContextProvider = newValue }
    }

    func performRequests() {
        controller.delegate = self
        controller.performRequests()
    }

    func cancel() {
        if #available(iOS 16.0, *) {
            controller.cancel()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let credential = (authorization.credential as? ASAuthorizationAppleIDCredential).map {
            SignInWithAppleAuthorization(user: $0.user, state: $0.state, identityToken: $0.identityToken)
        }
        delegate?.authorizationController(self, didCompleteWithAuthorization: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        delegate?.authorizationController(self, didCompleteWithError: error)
    }
}

@objc(OwnIDSignInWithAppleImpl)
internal final class SignInWithAppleImpl: NSObject, SignInWithApple, @unchecked Sendable {
    private let uiContextProvider: any UIContextProvider
    private let logger: OwnIDLogRouter?
    private let authorizationControllerFactory: @MainActor (ASAuthorizationAppleIDRequest) -> any SignInWithAppleAuthorizationController

    private var window: UIWindow?
    private var authController: (any SignInWithAppleAuthorizationController)?
    private var continuation: CheckedContinuation<SocialResult, Never>?
    private var cancelRequested = false
    private var expectedState: String?

    init(
        uiContextProvider: any UIContextProvider,
        logger: OwnIDLogRouter?,
        authorizationControllerFactory: @escaping @MainActor (ASAuthorizationAppleIDRequest) -> any SignInWithAppleAuthorizationController =
            {
                ASAuthorizationControllerAdapter(request: $0)
            }
    ) {
        self.uiContextProvider = uiContextProvider
        self.logger = logger
        self.authorizationControllerFactory = authorizationControllerFactory
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

            let authorizationController = authorizationControllerFactory(request)
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

extension SignInWithAppleImpl: SignInWithAppleAuthorizationControllerDelegate {
    @MainActor
    func authorizationController(
        _ controller: any SignInWithAppleAuthorizationController,
        didCompleteWithAuthorization authorization: SignInWithAppleAuthorization?
    ) {
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

        guard let authorization, let identityToken = authorization.identityToken
        else {
            continuation?.resume(returning: .fail(error: SocialResult.Error.general("Data missing")))
            return
        }

        guard authorization.state == expectedState else {
            continuation?.resume(returning: .fail(error: SocialResult.Error.general("Apple authorization response state mismatch")))
            return
        }

        continuation?.resume(
            returning: .success(
                id: authorization.user,
                idToken: String(decoding: identityToken, as: UTF8.self)
            )
        )
    }

    @MainActor
    func authorizationController(_ controller: any SignInWithAppleAuthorizationController, didCompleteWithError error: any Error) {
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
