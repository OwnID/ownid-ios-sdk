import Foundation
import UIKit

/// UI capability used by ``SignInWithGoogleOperation`` to present Google Sign-In.
///
/// This capability is backed by the app-registered ``SignInWithGoogle`` provider. Core forwards the OIDC client ID,
/// nonce, and presentation window to that provider and consumes the returned ``SocialResult``.
public protocol SignInWithGoogleUI: OperationUI {
    /// Presents Google Sign-In and returns the provider result.
    ///
    /// - Parameters:
    ///   - clientID: The OAuth web client ID configured for Google Sign-In.
    ///   - nonce: Optional OIDC nonce. OwnID passes the active challenge ID so the provider can bind it to the returned
    ///     ID token when supported.
    ///   - window: An optional window to present the sign-in UI from.
    /// - Returns: The sign-in result containing the ID token, a provider cancellation, or a provider/UI failure surfaced
    ///   as ``SocialResult/fail(error:)``.
    @MainActor func signIn(clientID: String, nonce: String?, window: UIWindow?) async -> SocialResult

    /// Requests best-effort cancellation of an in-progress Google Sign-In request.
    @MainActor func cancel()
}
