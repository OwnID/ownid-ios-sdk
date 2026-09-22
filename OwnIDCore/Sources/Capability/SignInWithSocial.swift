import UIKit

/// Parameters for ``SignInWithSocial``.
///
/// OwnID supplies these values from the current social challenge when it invokes a provider.
public struct SignInWithSocialParams: CapabilityParams, Sendable {
    /// OAuth client ID expected by the provider challenge.
    public let clientID: String
    /// Optional OIDC nonce that the provider should bind to the returned ID token when supported.
    public let nonce: String?

    /// Creates social sign-in parameters.
    ///
    /// - Parameters:
    ///   - clientID: OAuth client ID expected by the provider challenge.
    ///   - nonce: Optional OIDC nonce that the provider should bind to the returned ID token when supported.
    public init(clientID: String, nonce: String?) {
        self.clientID = clientID
        self.nonce = nonce
    }
}

/// Social sign-in capability for provider integrations.
///
/// Implementations launch provider UI through ``signIn(window:params:)`` and return
/// ``SocialResult/success(id:idToken:)``, ``SocialResult/canceled(reason:)``, or ``SocialResult/fail(error:)``. The
/// provider owns provider SDK setup, UI presentation, failure mapping, and any local provider session state.
///
/// ``isAvailable(params:)`` defaults to `true`. Override it when provider state, app configuration, or request
/// parameters can make social sign-in unavailable.
///
/// OwnID calls ``signIn(window:params:)`` and ``cancel()`` on the main actor because they usually present platform UI.
/// Cancellation via ``cancel()`` is best-effort and depends on provider API support.
/// OwnID treats ``SocialResult/canceled(reason:)`` as cancellation and ``SocialResult/fail(error:)`` as a
/// provider-owned failure.
public protocol SignInWithSocial: Capability, Sendable {
    /// Starts a provider challenge and presents social sign-in UI.
    ///
    /// OwnID supplies a window selected for the current request. Use it as the provider SDK's presentation anchor for
    /// this request, and release any retained reference when the request completes. The provider is responsible for
    /// validating ``SignInWithSocialParams/clientID`` and may bind ``SignInWithSocialParams/nonce`` to the issued ID
    /// token. The nonce value is server-provided challenge material; avoid logging or persisting it.
    ///
    /// Return ``SocialResult/success(id:idToken:)`` only after obtaining an ID token. Return
    /// ``SocialResult/canceled(reason:)`` for user or system cancellation, and ``SocialResult/fail(error:)`` for
    /// provider SDK, credential, presentation, or configuration failures. Avoid logging or persisting ID tokens or nonces.
    ///
    /// - Parameter window: Window to use as the provider SDK's presentation anchor for this request.
    /// - Parameter params: Social sign-in parameters.
    /// - Returns: ``SocialResult`` with the credential data, a cancellation, or a failure.
    @MainActor func signIn(window: UIWindow, params: SignInWithSocialParams) async -> SocialResult

    /// Requests cancellation of an active social sign-in request.
    ///
    /// Cancellation support is provider-dependent. Providers that cannot cancel the underlying identity-provider
    /// request should perform best-effort UI cleanup and allow the active request to finish normally. Errors thrown by
    /// underlying provider cleanup should be handled inside the provider because this callback has no failure result.
    @MainActor func cancel()
}

/// Outcome of a social sign-in attempt.
///
/// The provider chooses the result category. Return ``success(id:idToken:)`` only after obtaining an OIDC ID token;
/// OwnID treats ``canceled(reason:)`` as cancellation and ``fail(error:)`` as a provider-side failure.
public enum SocialResult: Sendable {
    /// Error details for a failed social sign-in.
    public enum Error: Sendable, LocalizedError {
        /// Provider SDK, credential, presentation, or configuration failure.
        case general(_ message: String, _ error: (any Swift.Error & Sendable)? = nil)

        /// Diagnostic text for the failure, falling back to the underlying error when the provider message is empty.
        public var errorDescription: String? {
            switch self {
            case .general(let message, let error):
                if !message.isEmpty { return message }
                if let error = error { return error.localizedDescription }
                return "An unknown error occurred."
            }
        }
    }

    /// Successful result carrying provider identity data.
    ///
    /// - Parameters:
    ///   - id: Provider user identifier metadata from the returned social credential. This value is optional for OwnID
    ///     completion and may be empty when the provider does not supply one.
    ///   - idToken: OIDC ID token required to complete social sign-in. Treat this value as sensitive authentication data.
    case success(id: String, idToken: String)
    /// Canceled by the user, system UI, or provider, with a reason.
    case canceled(reason: Reason)
    /// Failed before an ID token was obtained.
    case fail(error: Error)
}

/// Social sign-in via Google.
///
/// Host apps provide this capability through ``OwnIDProvidersRegistrar/signInWithGoogle(_:)``.
///
/// Adds Google-specific local session cleanup via ``signOut()``. For ``signIn(window:params:)``,
/// ``SignInWithSocialParams/clientID`` is the Google web/server OAuth client ID and
/// ``SignInWithSocialParams/nonce`` is forwarded to Google Identity as an optional OIDC nonce when the provider
/// supports it.
public protocol SignInWithGoogle: SignInWithSocial {
    /// Clears local Google sign-in state owned by the provider.
    ///
    /// This is local cleanup for the app/provider integration. It does not revoke OAuth consent grants or clear OwnID
    /// session state unless the provider does so explicitly.
    @MainActor func signOut()
}

/// Social sign-in via Apple.
///
/// OwnID Core registers this capability by default using AuthenticationServices. It is not configured through
/// ``OwnIDProvidersRegistrar``.
///
/// The default implementation presents `ASAuthorizationController`, uses ``SignInWithSocialParams/nonce`` for the
/// Apple request nonce, and uses the window supplied to ``signIn(window:params:)`` as its presentation anchor.
/// Cancellation is best-effort and uses platform cancellation APIs where available.
public protocol SignInWithApple: SignInWithSocial {}
