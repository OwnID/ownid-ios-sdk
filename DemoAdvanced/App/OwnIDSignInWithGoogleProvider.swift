import GoogleSignIn
@_spi(OwnIDInternal) import OwnIDCore
import UIKit

extension OwnIDProvidersRegistrar {
    @MainActor
    private enum GoogleSignInProviderState {
        static var isActive = false
    }

    /// Registers a GoogleSignIn-backed Google sign-in helper on this registrar.
    ///
    /// Register this source-only helper inside a providers block. It is not part of the `OwnIDCore` or `OwnIDSwiftUI`
    /// package products, is not a separate product, and depends on the host target compiling and linking `GoogleSignIn`.
    ///
    /// Use ``OwnID/setProviders(_:)`` to update providers in the current scope,
    /// or ``OwnID/withProviders(_:_:)`` to register Google Sign-In only in the returned child scope.
    ///
    /// It registers a Google implementation through ``OwnIDProvidersRegistrar/signInWithGoogle(_:)`` so OwnID can
    /// resolve ``SignInWithGoogle`` from the scope where this provider is registered.
    ///
    /// Behavior:
    /// - Uses the Google web/server client ID and optional `nonce` supplied in the provider callback parameters.
    /// - Forwards the nonce to GoogleSignIn when present; treat ID tokens and nonces as sensitive authentication data.
    /// - Resolves a presentation anchor using `presentingViewControllerProvider`, or falls back to ``UIContextProvider``.
    /// - Applies `GIDSignIn.sharedInstance.configuration` before each request.
    /// - Reports available for Google sign-in parameters.
    /// - Runs sign-in, cancellation, and sign-out handlers on the main actor through the ``SignInWithSocial`` and
    ///   ``SignInWithGoogle`` contracts.
    /// - Supports one active sign-in request at a time across all provider registrations; overlapping requests fail
    ///   immediately.
    /// - Returns ``SocialResult/success(id:idToken:)`` only when a non-empty Google ID token is returned.
    /// - Maps provider cancellation and cooperative Swift task cancellation to
    ///   ``SocialResult/canceled(reason:)`` with ``Reason/userClose(details:)``.
    /// - Returns ``SocialResult/fail(error:)`` for empty server or iOS client IDs, a missing reversed iOS-client
    ///   callback URL scheme, missing presenters, missing ID tokens, and non-cancellation GoogleSignIn failures.
    ///
    /// Source-only integration notes:
    /// - The OwnID challenge `clientID` is the Google web/server client ID. Use it as `serverClientID` when building
    ///   `GIDConfiguration` for backend ID token validation.
    /// - GoogleSignIn-iOS also requires the app's iOS OAuth client ID as `clientID`. Provide it from app configuration:
    ///   `GIDConfiguration(clientID: iosClientID, serverClientID: ownIDClientID)`.
    /// - This helper sets `GIDSignIn.sharedInstance.configuration` programmatically before sign-in, so the
    ///   `configurationProvider` must supply the full GoogleSignIn configuration for the request.
    /// - The host target must register the reversed iOS OAuth client ID as a callback URL scheme and forward callback
    ///   URLs to GoogleSignIn; scheme matching is case-insensitive.
    ///
    /// Cancellation notes:
    /// - An already-canceled Swift task returns cancellation without starting sign-in.
    /// - Canceling a Swift task does not dismiss provider UI immediately. The helper returns cancellation after the
    ///   active provider attempt completes.
    /// - GoogleSignIn does not expose direct cancellation, so the helper cannot guarantee immediate provider UI dismissal
    ///   or physical cancellation of an active request.
    /// - A new sign-in request is still rejected until the active attempt completes.
    /// - `cancelHandler` is invoked for app-owned cleanup. Dismiss only UI whose ownership the app can establish.
    ///
    /// Sign-out:
    /// - Calls `GIDSignIn.sharedInstance.signOut()` for local GoogleSignIn cleanup.
    /// - This is local provider/app cleanup. It does not revoke OAuth consent grants or clear OwnID session state.
    ///
    /// - Parameters:
    ///   - configurationProvider: Required factory that receives the OwnID challenge Google web/server client ID and
    ///     returns a `GIDConfiguration` for the current request.
    ///   - presentingViewControllerProvider: Optional custom presenter resolver for apps with non-standard scene/container
    ///     hierarchies.
    ///   - cancelHandler: Optional callback invoked on cancel for app-owned cleanup.
    @MainActor
    mutating func signInWithGoogleProvider(
        configurationProvider: @escaping (String) -> GIDConfiguration,
        presentingViewControllerProvider: (() -> UIViewController?)? = nil,
        cancelHandler: (() -> Void)? = nil
    ) {
        let logger = getOrNil(type: OwnIDLogRouter.self)
        let uiContextProvider = try? getOrThrow(type: (any UIContextProvider).self)

        func configurationError(_ configuration: GIDConfiguration, registeredURLSchemes: [String]) -> SocialResult.Error? {
            guard !configuration.clientID.isEmpty else {
                return .general("Google iOS clientID is empty")
            }

            let requiredScheme = configuration.clientID
                .split(separator: ".", omittingEmptySubsequences: false)
                .reversed()
                .joined(separator: ".")
            guard registeredURLSchemes.contains(where: { $0.caseInsensitiveCompare(requiredScheme) == .orderedSame }) else {
                return .general("Google iOS clientID callback URL scheme is not registered")
            }
            return nil
        }

        func registeredURLSchemes(in bundle: Bundle) -> [String] {
            guard let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [Any] else {
                return []
            }
            return urlTypes.flatMap { urlType -> [String] in
                guard
                    let urlType = urlType as? [String: Any],
                    let schemes = urlType["CFBundleURLSchemes"] as? [Any]
                else {
                    return []
                }
                return schemes.compactMap { $0 as? String }
            }
        }

        signInWithGoogle { provider in
            provider.signIn { params in
                guard !Task.isCancelled else {
                    return .canceled(reason: .userClose())
                }
                guard !GoogleSignInProviderState.isActive else {
                    return .fail(error: .general("Another Google sign-in request is already in progress"))
                }
                GoogleSignInProviderState.isActive = true
                defer {
                    GoogleSignInProviderState.isActive = false
                }

                guard !params.clientID.isEmpty else {
                    return .fail(error: .general("Google server clientID is empty"))
                }
                let presentingViewController =
                    presentingViewControllerProvider?()
                    ?? uiContextProvider?.topMostViewController(params.window ?? uiContextProvider?.activeWindow())

                guard let presentingViewController else {
                    return .fail(error: .general("Cannot resolve a presenting view controller for Google Sign-In"))
                }

                let configuration = configurationProvider(params.clientID)
                if let error = configurationError(
                    configuration,
                    registeredURLSchemes: registeredURLSchemes(in: .main)
                ) {
                    return .fail(error: error)
                }

                GIDSignIn.sharedInstance.configuration = configuration

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
                    guard !Task.isCancelled else {
                        return .canceled(reason: .userClose())
                    }
                    guard let idToken = signInResult.user.idToken?.tokenString, !idToken.isEmpty else {
                        return .fail(error: .general("Google Sign-In did not return an ID token"))
                    }
                    return .success(id: signInResult.user.userID ?? "", idToken: idToken)
                } catch is CancellationError {
                    return .canceled(reason: .userClose())
                } catch {
                    guard !Task.isCancelled else {
                        return .canceled(reason: .userClose())
                    }
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
                cancelHandler?()
            }
            provider.signOut {
                GIDSignIn.sharedInstance.signOut()
            }
        }
    }
}
