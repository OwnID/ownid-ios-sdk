import GoogleSignIn
@_spi(OwnIDInternal) import OwnIDCore
import UIKit

extension OwnIDProvidersRegistrar {
    /// Registers a source-only GoogleSignInProvider implementation for Google social sign-in.
    ///
    /// ### Registration
    ///
    /// Call this helper inside ``OwnID/setProviders(_:)`` to register it in the current provider scope. Use
    /// ``OwnID/withProviders(_:_:)`` when Sign in with Google should be available only through the returned child scope.
    /// This source-only helper is not included in the `OwnIDCore` or `OwnIDSwiftUI` products. The host target must link
    /// `GoogleSignIn`.
    ///
    /// The host app must also:
    ///
    /// - Register the reversed iOS OAuth client ID as a callback URL scheme.
    /// - Forward callback URLs to `GIDSignIn.sharedInstance.handle(_:)`.
    ///
    /// ### Google configuration
    ///
    /// The OwnID challenge provides the Google web/server client ID. When OwnID proceeds with provider configuration,
    /// `configurationProvider` receives that value on the main actor and must return a request-specific
    /// `GIDConfiguration`:
    ///
    /// - Set `clientID` to the app's Google iOS OAuth client ID.
    /// - Set `serverClientID` to the supplied web/server client ID. This is the audience of the returned OIDC ID token.
    ///
    /// Before starting GoogleSignIn, the helper rejects an empty challenge web/server client ID or iOS client ID and
    /// verifies that the iOS client's reversed form is registered as a callback URL scheme.
    ///
    /// ### Presentation and credentials
    ///
    /// OwnID supplies the exact `UIWindow` for each invocation. The helper resolves the presenter only from that window
    /// and does not search application-global window state. Sign-in fails when no presenter can be resolved from the
    /// supplied window.
    ///
    /// A non-empty OwnID nonce is forwarded to GoogleSignIn. Nonces and returned ID tokens are sensitive authentication
    /// data; do not log or persist them.
    ///
    /// ### Results
    ///
    /// The helper maps outcomes as follows:
    ///
    /// - Returns ``SocialSignInResult/success(id:idToken:)`` only when GoogleSignIn supplies a non-empty ID token. The Google
    ///   user ID is included when available and may otherwise be empty.
    /// - Returns ``SocialSignInResult/canceled(reason:)`` for a thrown `CancellationError`, GoogleSignIn user cancellation, or
    ///   cooperative Swift task cancellation.
    /// - Returns ``SocialSignInResult/fail(error:)`` for an empty challenge web/server or iOS client ID, a missing callback
    ///   URL scheme or presenter, a missing ID token, and non-cancellation GoogleSignIn failures.
    ///
    /// Only one Sign in with Google request can be active at a time across all registrations in the process. An overlapping
    /// request fails immediately, and a new request remains blocked until the active GoogleSignIn attempt completes.
    ///
    /// ### Cancellation
    ///
    /// An already-canceled Swift task returns cancellation without starting GoogleSignIn. Canceling a task after its
    /// GoogleSignIn attempt has started does not dismiss or cancel active Google authorization UI; GoogleSignIn does not
    /// expose an API for that. The helper reports task cancellation after the active provider attempt completes.
    ///
    /// `cancelHandler` runs on the main actor when OwnID requests cancellation and is only for app-owned cleanup. Dismiss
    /// only UI whose ownership the app can establish; this callback cannot guarantee cancellation of GoogleSignIn UI.
    ///
    /// ### Sign-out
    ///
    /// Sign-out calls `GIDSignIn.sharedInstance.signOut()` to remove the current Google user from local keychain state.
    /// It does not revoke OAuth consent grants or clear OwnID session state.
    ///
    /// - Parameters:
    ///   - configurationProvider: Main-actor factory that creates request-specific configuration from the OwnID web/server
    ///     client ID.
    ///   - cancelHandler: Optional main-actor callback for app-owned cancellation cleanup.
    @MainActor
    mutating func googleSignInProvider(
        configurationProvider: @escaping (String) -> GIDConfiguration,
        cancelHandler: (() -> Void)? = nil
    ) {
        let logger = getOrNil(type: OwnIDLogRouter.self)

        googleSignIn { provider in
            provider.signIn { window, params in
                await GoogleSignInProviderImplementation.signIn(
                    window: window,
                    params: params,
                    configurationProvider: configurationProvider,
                    logger: logger
                )
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

@MainActor
private enum GoogleSignInProviderImplementation {
    static var isActive = false

    static func signIn(
        window: UIWindow,
        params: SocialSignInParams,
        configurationProvider: (String) -> GIDConfiguration,
        logger: OwnIDLogRouter?
    ) async -> SocialSignInResult {
        guard !Task.isCancelled else {
            return .canceled(reason: .userClose())
        }
        guard !isActive else {
            return .fail(error: .general("Another Sign in with Google request is already in progress"))
        }
        isActive = true
        defer {
            isActive = false
        }

        guard !params.clientID.isEmpty else {
            return .fail(error: .general("Google server clientID is empty"))
        }
        guard let presentingViewController = resolvePresentingViewController(in: window) else {
            let message = "Cannot resolve a presenting view controller for Sign in with Google"
            logger?.logW(source: OwnIDProvidersRegistrar.self, prefix: "googleSignIn", message: message)
            return .fail(error: .general(message))
        }

        let configuration = configurationProvider(params.clientID)
        if let error = configurationError(configuration) {
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
                return .fail(error: .general("Sign in with Google did not return an ID token"))
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
                source: OwnIDProvidersRegistrar.self,
                prefix: "googleSignIn",
                message: "Sign in with Google failed: \(error.localizedDescription)",
                cause: error
            )
            return .fail(error: .general("Sign in with Google failed", error))
        }
    }

    static func resolvePresentingViewController(in window: UIWindow) -> UIViewController? {
        func isCoherent(_ controller: UIViewController) -> Bool {
            guard let controllerWindow = controller.viewIfLoaded?.window else { return true }
            return controllerWindow === window
        }

        guard let rootController = window.rootViewController, isCoherent(rootController) else { return nil }

        var current = rootController
        var visited = Set<ObjectIdentifier>()
        visited.insert(ObjectIdentifier(current))

        func eligibleController(_ candidate: UIViewController?) -> UIViewController? {
            guard let candidate, !candidate.isBeingDismissed else { return nil }
            let identity = ObjectIdentifier(candidate)
            guard !visited.contains(identity), isCoherent(candidate) else { return nil }
            return candidate
        }

        while let next = eligibleController(current.presentedViewController)
            ?? eligibleController((current as? UINavigationController)?.visibleViewController)
            ?? eligibleController((current as? UITabBarController)?.selectedViewController)
        {
            visited.insert(ObjectIdentifier(next))
            current = next
        }

        return current
    }

    static func configurationError(_ configuration: GIDConfiguration) -> SocialSignInResult.Error? {
        guard !configuration.clientID.isEmpty else {
            return .general("Google iOS clientID is empty")
        }

        let requiredScheme = configuration.clientID
            .split(separator: ".", omittingEmptySubsequences: false)
            .reversed()
            .joined(separator: ".")
        let registeredURLSchemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [Any] ?? [])
            .flatMap { urlType -> [String] in
                guard
                    let urlType = urlType as? [String: Any],
                    let schemes = urlType["CFBundleURLSchemes"] as? [Any]
                else {
                    return []
                }
                return schemes.compactMap { $0 as? String }
            }
        guard registeredURLSchemes.contains(where: {
            $0.caseInsensitiveCompare(requiredScheme) == .orderedSame
        }) else {
            return .general("Google iOS clientID callback URL scheme is not registered")
        }
        return nil
    }
}
