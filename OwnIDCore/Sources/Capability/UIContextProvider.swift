import Foundation
import UIKit

/// Resolves the app UI context that an SDK presentation needs.
///
/// A provider may select the current app window, follow a specific window or scene, or supply a context owned by a
/// host integration. Resolution is synchronous on the main actor. Call it immediately before starting UI that needs
/// the context because a successful lookup does not guarantee that the window or controller will remain presentable.
/// The returned result is authoritative; a failure does not fall back to another provider.
///
/// When the app does not register an override, OwnID selects an eligible foreground application window at lookup.
/// Register an explicit window, scene, or custom provider when presentation must remain bound to a specific owner.
public protocol UIContextProvider: Sendable {
    /// Returns the current UI context, or the provider's failure when no usable context is available.
    ///
    /// Call this after asynchronous preparation and immediately before native presentation. A provider must not wait
    /// for a host callback from this synchronous lookup; return ``UIContextResult/failure(_:)`` instead when the host
    /// is not ready.
    @MainActor func current() -> UIContextResult
}

/// The result of a UI context lookup.
public enum UIContextResult {
    /// A window is available, but no presentation controller was supplied.
    ///
    /// Return this when a window is available but the provider cannot supply a matching presentation controller. A
    /// consumer that requires a view controller treats this as a resolution failure rather than selecting another
    /// window or controller.
    case windowOnly(UIWindow)
    /// A window and a presentation controller belonging to that same window are available.
    case windowAndController(window: UIWindow, controller: UIViewController)
    /// The provider could not supply a usable context.
    ///
    /// The error is provider-owned.
    case failure(any Swift.Error)
}

/// A built-in failure to resolve a UI context.
///
/// Use ``reason`` for programmatic handling and ``message`` or ``errorDescription`` for diagnostics.
public struct UIContextResolutionError: Swift.Error, Sendable, LocalizedError {
    /// The machine-readable reason for the failure.
    public enum Reason: Sendable, Equatable {
        /// No suitable context is currently available. A later lookup may succeed, but recovery is not guaranteed.
        case unavailable
        /// The provider's bound window, scene, WebView, or other owner has ended and should be recreated or rebound.
        case ownerClosed
    }

    /// The failure reason.
    public let reason: Reason
    /// Provider-specific diagnostic text; use ``reason`` for programmatic decisions.
    public let message: String
    /// An optional underlying error that caused resolution to fail.
    public let cause: (any Swift.Error)?

    /// Creates a resolution error with a reason, diagnostic message, and optional cause.
    public init(reason: Reason, message: String, cause: (any Swift.Error)? = nil) {
        self.reason = reason
        self.message = message
        self.cause = cause
    }

    /// A concise diagnostic containing the reason, provider message, and optional underlying cause.
    public var errorDescription: String? {
        let reasonDescription: String
        switch reason {
        case .unavailable:
            reasonDescription = "UI context unavailable"
        case .ownerClosed:
            reasonDescription = "UI context owner closed"
        }

        let description = "\(reasonDescription): \(message)"
        guard let cause else { return description }
        return "\(description) Cause: \(cause.localizedDescription)"
    }
}
