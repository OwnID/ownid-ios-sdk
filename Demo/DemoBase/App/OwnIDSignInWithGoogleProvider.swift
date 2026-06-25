import GoogleSignIn
@_spi(OwnIDInternal) import OwnIDCore
import UIKit

extension OwnIDProvidersRegistrar {
    /// Registers a GoogleSignIn-backed ``SignInWithGoogle`` handler on this registrar.
    ///
    /// Register this source-only helper inside a providers block. It is not part of the `OwnIDCore` or `OwnIDSwiftUI`
    /// package products and depends on the host target compiling and linking `GoogleSignIn`.
    ///
    /// Use ``OwnID/setProviders(_:)`` to update provider bindings in the current scope,
    /// or ``OwnID/withProviders(_:_:)`` to register Google Sign-In only in the returned child scope.
    ///
    /// It binds a Google implementation through ``OwnIDProvidersRegistrar/signInWithGoogle(_:)`` so Google OIDC operations
    /// and WebBridge social actions can resolve ``SignInWithGoogle`` from the scope where this provider is registered.
    ///
    /// Behavior:
    /// - Uses the Google web/server client ID and optional `nonce` provided by the current OwnID OIDC challenge flow.
    /// - Resolves a presentation anchor using `presentingViewControllerProvider`, or falls back to ``UIContextProvider``.
    /// - Applies `GIDSignIn.sharedInstance.configuration` before each request.
    /// - Supports one active sign-in request at a time; overlapping requests fail immediately.
    /// - Returns ``SocialResult/success(id:idToken:)`` only when a non-empty Google ID token is returned.
    /// - Maps Google SDK cancellation and Swift task cancellation to ``SocialResult/canceled(reason:)`` with
    ///   ``Reason/userClose(details:)``.
    ///
    /// Source-only integration notes:
    /// - The OwnID challenge `clientID` is the Google web/server client ID. Use it as `serverClientID` when building
    ///   `GIDConfiguration` for backend ID token validation.
    /// - GoogleSignIn-iOS also requires the app's iOS OAuth client ID as `clientID`. Provide it from app configuration:
    ///   `GIDConfiguration(clientID: iosClientID, serverClientID: ownIDClientID)`.
    /// - This helper sets `GIDSignIn.sharedInstance.configuration` programmatically before sign-in, so the
    ///   `configurationProvider` must supply the full GoogleSignIn configuration for the request.
    /// - The host target remains responsible for GoogleSignIn app setup, including URL handling required by that SDK.
    ///
    /// Cancellation notes:
    /// - GoogleSignIn iOS SDK does not expose a direct API to cancel an in-flight authorization request.
    /// - `cancel()` performs best-effort UI dismissal by closing the currently presented authorization controller (if any).
    /// - `cancelHandler` is invoked after this best-effort dismissal and is intended for app-local cleanup only.
    ///
    /// - Parameters:
    ///   - configurationProvider: Required factory that receives the OwnID challenge Google web/server client ID and
    ///     returns a `GIDConfiguration` for the current request.
    ///   - presentingViewControllerProvider: Optional custom presenter resolver for apps with non-standard scene/container
    ///     hierarchies.
    ///   - cancelHandler: Optional callback invoked on cancel for app-specific cleanup.
    @MainActor
    mutating func signInWithGoogleProvider(
        configurationProvider: @escaping (String) -> GIDConfiguration,
        presentingViewControllerProvider: (() -> UIViewController?)? = nil,
        cancelHandler: (() -> Void)? = nil
    ) {
        let logger = getOrNil(type: OwnIDLogRouter.self)
        let uiContextProvider = try? getOrThrow(type: (any UIContextProvider).self)
        var activePresenter: UIViewController?
        var isSigningIn = false

        signInWithGoogle { provider in
            provider.signIn { params in
                guard !isSigningIn else {
                    return .fail(error: .general("Another Google sign-in request is already in progress"))
                }
                isSigningIn = true
                defer {
                    isSigningIn = false
                    activePresenter = nil
                }

                guard !params.clientID.isEmpty else {
                    return .fail(error: .general("Google clientID is empty"))
                }
                let presentingViewController =
                    presentingViewControllerProvider?()
                    ?? uiContextProvider?.topMostViewController(params.window ?? uiContextProvider?.activeWindow())

                guard let presentingViewController else {
                    return .fail(error: .general("Cannot resolve a presenting view controller for Google Sign-In"))
                }

                activePresenter = presentingViewController

                GIDSignIn.sharedInstance.configuration = configurationProvider(params.clientID)

                do {
                    let signInResult: GIDSignInResult
                    if let nonce = params.nonce, !nonce.isEmpty {
                        signInResult = try await GIDSignIn.sharedInstance.signIn(
                            withPresenting: presentingViewController,
                            hint: nil,
                            additionalScopes: nil,
                            nonce: nonce
                        )
                    } else {
                        signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
                    }
                    guard let idToken = signInResult.user.idToken?.tokenString, !idToken.isEmpty else {
                        return .fail(error: .general("Google Sign-In did not return an ID token"))
                    }
                    return .success(id: signInResult.user.userID ?? "", idToken: idToken)
                } catch is CancellationError {
                    return .canceled(reason: .userClose())
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == kGIDSignInErrorDomain, nsError.code == GIDSignInError.Code.canceled.rawValue {
                        return .canceled(reason: .userClose())
                    }
                    logger?.logW(
                        source: Self.self,
                        prefix: "signInWithGoogle",
                        message: "Google sign-in failed: \(error.localizedDescription)",
                        cause: error
                    )
                    return .fail(error: .general("Google Sign-In failed", error))
                }
            }
            provider.cancel {
                // GoogleSignIn SDK has no direct cancel API; dismiss presented authorization UI best-effort.
                if let presented = activePresenter?.presentedViewController {
                    presented.dismiss(animated: true)
                }
                cancelHandler?()
            }
            provider.signOut {
                GIDSignIn.sharedInstance.signOut()
            }
        }
    }
}
