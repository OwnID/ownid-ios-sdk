import Foundation
import UIKit

/// UI capability used by ``SignInWithGoogleOperation`` to run Sign in with Google.
///
/// Implementations receive the active challenge values and own the provider-specific presentation details. Return
/// ``SocialSignInResult/fail(error:)`` when the request cannot be presented or completed.
/// The default implementation resolves a window from the current ``UIContextProvider`` immediately before invoking
/// the Google provider and returns a provider/UI failure when no presentation window is available.
public protocol SignInWithGoogleUI: OperationUI {
    /// Starts Sign in with Google for the active challenge.
    ///
    /// - Parameters:
    ///   - clientID: The Google web/server OAuth client identifier from the active challenge.
    ///   - nonce: Optional OIDC nonce from the active challenge. Pass it to the provider when supported so it can bind
    ///     the returned ID token.
    /// - Returns: The sign-in result containing the ID token, a provider cancellation, or a provider/UI failure surfaced
    ///   as ``SocialSignInResult/fail(error:)``.
    @MainActor func signIn(clientID: String, nonce: String?) async -> SocialSignInResult

    /// Requests best-effort cancellation of an in-progress Sign in with Google request.
    @MainActor func cancel()
}
