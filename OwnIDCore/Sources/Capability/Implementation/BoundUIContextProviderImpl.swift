import UIKit

@MainActor
internal final class WindowUIContextProviderImpl: UIContextProvider {
    private weak var window: UIWindow?

    internal init(window: UIWindow) {
        self.window = window
    }

    internal func current() -> UIContextResult {
        guard let window else {
            return .failure(
                UIContextResolutionError(
                    reason: .ownerClosed,
                    message: "The bound window owner is no longer available."
                )
            )
        }

        return UIContextWindowResolver.resolve(window: window)
    }
}

@MainActor
internal final class WindowSceneUIContextProviderImpl: UIContextProvider {
    private let sessionIdentifier: String

    internal init(scene: UIWindowScene) {
        self.sessionIdentifier = scene.session.persistentIdentifier
    }

    internal func current() -> UIContextResult {
        let application = UIApplication.shared
        let connectedScene = application.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.persistentIdentifier == sessionIdentifier }

        guard let connectedScene else {
            let isSessionOpen = application.openSessions.contains {
                $0.persistentIdentifier == sessionIdentifier
            }
            return .failure(
                UIContextResolutionError(
                    reason: isSessionOpen ? .unavailable : .ownerClosed,
                    message: isSessionOpen
                        ? "The bound window scene is not currently connected."
                        : "The bound window scene session is no longer available."
                )
            )
        }

        guard
            let window = connectedScene.windows
                .filter({ $0.windowScene === connectedScene })
                .sorted(by: isWindowOrderedBefore)
                .first
        else {
            return .failure(
                UIContextResolutionError(
                    reason: .unavailable,
                    message: "The bound window scene has no associated windows."
                )
            )
        }

        return UIContextWindowResolver.resolve(window: window)
    }

    private func isWindowOrderedBefore(_ lhs: UIWindow, _ rhs: UIWindow) -> Bool {
        func rank(_ window: UIWindow) -> Int {
            if window.isKeyWindow { return 0 }
            if !window.isHidden, window.windowLevel == .normal { return 1 }
            if !window.isHidden { return 2 }
            if window.windowLevel == .normal { return 3 }
            return 4
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
