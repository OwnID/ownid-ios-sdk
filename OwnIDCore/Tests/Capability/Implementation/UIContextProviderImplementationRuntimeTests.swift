import Testing
import UIKit

@testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct UIContextProviderImplementationRuntimeTests {

    @Test func `Top-most controller follows presented navigation tab split and page hierarchy`() throws {
        let provider = UIContextProviderImpl()
        let window = TestWindow()
        defer { window.close() }

        let root = PresentingViewController()
        let navigation = UINavigationController()
        let tab = UITabBarController()
        let split = UISplitViewController()
        let page = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        let inactivePage = UIViewController()
        let expected = UIViewController()

        page.setViewControllers([expected], direction: .forward, animated: false)
        split.viewControllers = [inactivePage, page]
        tab.viewControllers = [UIViewController(), split]
        tab.selectedIndex = 1
        navigation.setViewControllers([UIViewController(), tab], animated: false)
        root.presentedOverride = navigation
        window.show(root: root)

        #expect(provider.topMostViewController(window) === expected)
    }

    @Test func `Presented controller is ignored while it is being dismissed`() {
        let provider = UIContextProviderImpl()
        let window = TestWindow()
        defer { window.close() }

        let root = PresentingViewController()
        root.presentedOverride = DismissingViewController()
        window.show(root: root)

        #expect(provider.topMostViewController(window) === root)
    }

    @Test func `Single visible content child is preferred`() {
        let provider = UIContextProviderImpl()
        let window = TestWindow()
        defer { window.close() }

        let root = UIViewController()
        let hidden = UIViewController()
        let empty = UIViewController()
        let detached = UIViewController()
        let expected = UIViewController()
        window.show(root: root)

        root.addTestChild(hidden)
        hidden.view.isHidden = true

        root.addTestChild(empty)
        empty.view.frame = .zero

        root.addChild(detached)
        detached.didMove(toParent: root)

        root.addTestChild(expected)

        #expect(provider.topMostViewController(window) === expected)
    }

    @Test func `Dismissed or ambiguous content children leave the parent as top-most`() {
        let provider = UIContextProviderImpl()
        let window = TestWindow()
        defer { window.close() }

        let root = UIViewController()
        window.show(root: root)

        root.addTestChild(DismissingViewController())
        root.addTestChild(UIViewController())
        root.addTestChild(UIViewController())

        #expect(provider.topMostViewController(window) === root)
    }

    @Test func `Missing root controller returns no top-most controller`() {
        let provider = UIContextProviderImpl()
        let window = TestWindow()
        defer { window.close() }

        window.makeKeyAndVisible()

        #expect(provider.topMostViewController(window) == nil)
    }
}

private final class TestWindow: UIWindow {
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        windowLevel = .normal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(root: UIViewController) {
        rootViewController = root
        makeKeyAndVisible()
        root.view.frame = bounds
        root.view.layoutIfNeeded()
    }

    func close() {
        isHidden = true
        rootViewController = nil
    }
}

private final class PresentingViewController: UIViewController {
    var presentedOverride: UIViewController?

    override var presentedViewController: UIViewController? {
        presentedOverride ?? super.presentedViewController
    }
}

private final class DismissingViewController: UIViewController {
    override var isBeingDismissed: Bool { true }
}

extension UIViewController {
    fileprivate func addTestChild(_ child: UIViewController) {
        loadViewIfNeeded()
        child.loadViewIfNeeded()
        addChild(child)
        child.view.frame = view.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 100, height: 100) : view.bounds
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }
}
