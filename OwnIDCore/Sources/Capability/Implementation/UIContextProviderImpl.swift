import UIKit

@MainActor
internal final class UIContextProviderImpl: UIContextProvider {
    nonisolated init() {}

    func current() -> UIContextResult {
        let application = UIApplication.shared

        if let window = modernWindow(in: application) {
            return UIContextWindowResolver.resolve(window: window)
        }

        let unavailable: UIContextResult = .failure(
            UIContextResolutionError(
                reason: .unavailable,
                message: "No eligible foreground application window is available."
            )
        )

        #if compiler(>=6.4)
            @diagnose(DeprecatedDeclaration, as: ignored, reason: "Legacy hosts without scene lifecycle have no UIWindowScene to query.")
        #endif
        func legacyWindows(in application: UIApplication) -> [UIWindow] {
            application.windows
        }

        guard UIContextLifecycleMode.isLegacy(in: application),
            application.applicationState == .active || application.applicationState == .inactive
        else {
            return unavailable
        }
        guard
            let window = legacyWindows(in: application)
                .filter({ !$0.isHidden && $0.windowScene == nil })
                .sorted(by: isWindowOrderedBefore)
                .first
        else {
            return unavailable
        }

        return UIContextWindowResolver.resolve(window: window)
    }

    private func modernWindow(in application: UIApplication) -> UIWindow? {
        let scenes = application.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter(isEligibleScene)
            .sorted(by: isSceneOrderedBefore)

        guard let scene = scenes.first else { return nil }
        return orderedWindows(in: scene).first
    }

    private func isEligibleScene(_ scene: UIWindowScene) -> Bool {
        switch scene.activationState {
        case .foregroundActive, .foregroundInactive:
            break
        default:
            return false
        }

        let role = scene.session.role
        guard role != .windowExternalDisplay else { return false }
        if #available(iOS 16.0, *), role == .windowExternalDisplayNonInteractive {
            return false
        }
        return !orderedWindows(in: scene).isEmpty
    }

    private func isSceneOrderedBefore(_ lhs: UIWindowScene, _ rhs: UIWindowScene) -> Bool {
        if lhs.activationState != rhs.activationState {
            return lhs.activationState == .foregroundActive
        }

        let lhsSessionID = lhs.session.persistentIdentifier
        let rhsSessionID = rhs.session.persistentIdentifier
        if lhsSessionID != rhsSessionID {
            return lhsSessionID < rhsSessionID
        }

        return numericIdentity(lhs) < numericIdentity(rhs)
    }

    private func orderedWindows(in scene: UIWindowScene) -> [UIWindow] {
        scene.windows
            .filter { !$0.isHidden && $0.windowScene === scene }
            .sorted(by: isWindowOrderedBefore)
    }

    private func isWindowOrderedBefore(_ lhs: UIWindow, _ rhs: UIWindow) -> Bool {
        func rank(_ window: UIWindow) -> Int {
            if window.isKeyWindow { return 0 }
            if window.windowLevel == .normal { return 1 }
            return 2
        }

        let lhsRank = rank(lhs)
        let rhsRank = rank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return numericIdentity(lhs) < numericIdentity(rhs)
    }

    private func numericIdentity(_ object: AnyObject) -> UInt {
        UInt(bitPattern: ObjectIdentifier(object))
    }
}

@MainActor
internal enum UIContextWindowResolver {
    internal static func resolve(window: UIWindow) -> UIContextResult {
        guard let rootController = window.rootViewController else {
            return .windowOnly(window)
        }
        guard isCoherent(rootController, with: window) else {
            return .windowOnly(window)
        }

        return .windowAndController(
            window: window,
            controller: topController(from: rootController, in: window)
        )
    }

    private static func topController(from rootController: UIViewController, in window: UIWindow) -> UIViewController {
        var current = rootController
        var visited = Set<ObjectIdentifier>()
        visited.insert(ObjectIdentifier(current))

        func eligibleController(_ candidate: UIViewController?) -> UIViewController? {
            guard let candidate, !candidate.isBeingDismissed else { return nil }
            let identity = ObjectIdentifier(candidate)
            guard !visited.contains(identity), isCoherent(candidate, with: window) else { return nil }
            return candidate
        }

        while let next = eligibleController(current.presentedViewController)
            ?? eligibleController((current as? UINavigationController)?.visibleViewController)
            ?? eligibleController((current as? UITabBarController)?.selectedViewController)
        {
            let identity = ObjectIdentifier(next)
            visited.insert(identity)
            current = next
        }

        return current
    }

    private static func isCoherent(_ controller: UIViewController, with window: UIWindow) -> Bool {
        guard let controllerWindow = controller.viewIfLoaded?.window else {
            return true
        }
        return controllerWindow === window
    }
}

/// Shared lifecycle classification for UIKit consumers that must distinguish a truly legacy nil-scene window from a
/// temporarily detached window in a scene-based app.
@_spi(OwnIDInternal)
public enum UIContextLifecycleMode {
    /// Returns `true` only when the process has no evidence that it uses the scene lifecycle.
    @MainActor
    public static func isLegacy(in application: UIApplication = .shared) -> Bool {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]

        if infoDictionary.keys.contains("UIApplicationSceneManifest") {
            return false
        }
        if !application.connectedScenes.isEmpty || !application.openSessions.isEmpty {
            return false
        }
        return true
    }
}

extension UIContextResult {
    @MainActor
    func requireWindow() throws -> UIWindow {
        switch self {
        case .windowOnly(let window):
            return window
        case .windowAndController(let window, _):
            return window
        case .failure(let error):
            throw error
        }
    }
}
