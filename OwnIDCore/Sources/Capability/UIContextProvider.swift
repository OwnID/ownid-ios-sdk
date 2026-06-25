import UIKit

/// Provides access to the current UI context for presenting SDK prompts.
///
/// UI-backed capabilities use this as a best-effort source for locating the app's current window and topmost
/// presentation controller. The default provider searches connected scenes on the main actor, preferring foreground
/// scenes and key or visible windows. Callers should tolerate `nil` when no scene can present UI.
public protocol UIContextProvider: Sendable {
    /// Returns the best active `UIWindow`, or `nil` if none is available.
    @MainActor func activeWindow() -> UIWindow?
    /// Returns the topmost visible view controller in the given window, or `nil` if no presentation anchor exists.
    @MainActor func topMostViewController(_ window: UIWindow?) -> UIViewController?
}
