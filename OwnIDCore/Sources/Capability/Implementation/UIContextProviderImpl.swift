import UIKit

internal final class UIContextProviderImpl: UIContextProvider {
    @MainActor
    func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { activationStateRank($0.activationState) < activationStateRank($1.activationState) }

        for scene in scenes {
            if let w = scene.windows.first(where: { $0.isKeyWindow }) { return w }
            if let w = scene.windows.first(where: { !$0.isHidden && $0.windowLevel == .normal }) { return w }
            if let w = scene.windows.first { return w }
        }
        return nil
    }

    @MainActor
    func topMostViewController(_ window: UIWindow?) -> UIViewController? {
        let baseWindow = window ?? activeWindow()
        guard let controller = baseWindow?.rootViewController else { return nil }
        return findTopViewController(from: controller)
    }

    @MainActor
    private func findTopViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            return findTopViewController(from: presented)
        }
        if let nav = controller as? UINavigationController, let visible = nav.visibleViewController {
            return findTopViewController(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return findTopViewController(from: selected)
        }
        if let split = controller as? UISplitViewController, let last = split.viewControllers.last {
            return findTopViewController(from: last)
        }
        if let page = controller as? UIPageViewController, let first = page.viewControllers?.first {
            return findTopViewController(from: first)
        }
        if let child = singleVisibleContentChild(of: controller) {
            return findTopViewController(from: child)
        }
        return controller
    }

    @MainActor
    private func singleVisibleContentChild(of controller: UIViewController) -> UIViewController? {
        var visibleChild: UIViewController?

        for child in controller.children where isVisibleContentChild(child) {
            guard visibleChild == nil else { return nil }
            visibleChild = child
        }

        return visibleChild
    }

    @MainActor
    private func isVisibleContentChild(_ child: UIViewController) -> Bool {
        guard !child.isBeingDismissed else { return false }
        guard let view = child.viewIfLoaded else { return false }
        guard view.window != nil else { return false }
        guard view.superview != nil else { return false }
        guard !view.isHidden else { return false }
        guard !view.bounds.isEmpty else { return false }
        return true
    }

    private func activationStateRank(_ state: UIScene.ActivationState) -> Int {
        switch state {
        case .foregroundActive: return 0
        case .foregroundInactive: return 1
        case .background: return 2
        default: return 3
        }
    }
}
