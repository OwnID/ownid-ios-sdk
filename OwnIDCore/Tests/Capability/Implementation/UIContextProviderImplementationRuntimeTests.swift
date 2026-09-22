import Testing
import UIKit

@testable import OwnIDCore

@MainActor
@Suite(.serialized)
// Covers: CFG-RUNTIME-080
struct UIContextProviderImplementationRuntimeTests {

    @Test func `Window resolver returns the selected window and deepest supported controller`() throws {
        let window = TestWindow()
        defer { window.close() }

        let root = PresentingViewController()
        let navigation = UINavigationController()
        let tab = UITabBarController()
        let firstTab = UIViewController()
        let expected = UIViewController()

        tab.viewControllers = [firstTab, expected]
        tab.selectedIndex = 1
        navigation.setViewControllers([UIViewController(), tab], animated: false)
        root.presentedOverride = navigation
        window.show(root: root)

        let result = WindowUIContextProviderImpl(window: window).current()

        guard case .windowAndController(let resolvedWindow, let controller) = result else {
            Issue.record("Expected a window and presentation controller")
            return
        }
        #expect(resolvedWindow === window)
        #expect(controller === expected)
    }

    @Test func `Dismissing presented controller is not returned`() {
        let window = TestWindow()
        defer { window.close() }

        let root = PresentingViewController()
        root.presentedOverride = DismissingViewController()
        window.show(root: root)

        let result = WindowUIContextProviderImpl(window: window).current()

        guard case .windowAndController(_, let controller) = result else {
            Issue.record("Expected the root controller to remain available")
            return
        }
        #expect(controller === root)
    }

    @Test func `Resolver returns a split container instead of selecting an arbitrary child pane`() {
        let window = TestWindow()
        defer { window.close() }

        let root = PresentingViewController()
        let split = UISplitViewController()
        split.viewControllers = [UIViewController(), UIViewController()]
        root.presentedOverride = split
        window.show(root: root)

        let result = WindowUIContextProviderImpl(window: window).current()

        guard case .windowAndController(_, let controller) = result else {
            Issue.record("Expected the split container to resolve as the presentation controller")
            return
        }
        #expect(controller === split)
    }

    @Test func `Resolver returns a page container instead of selecting its current page`() {
        let window = TestWindow()
        defer { window.close() }

        let root = PresentingViewController()
        let page = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        page.setViewControllers([UIViewController()], direction: .forward, animated: false)
        root.presentedOverride = page
        window.show(root: root)

        let result = WindowUIContextProviderImpl(window: window).current()

        guard case .windowAndController(_, let controller) = result else {
            Issue.record("Expected the page container to resolve as the presentation controller")
            return
        }
        #expect(controller === page)
    }

    @Test func `Root controller mounted in another window resolves as window only`() {
        let selectedWindow = TestWindow()
        let foreignWindow = TestWindow()
        defer {
            selectedWindow.close()
            foreignWindow.close()
        }

        let root = UIViewController()
        selectedWindow.showWithoutMakingKey(root: root)
        foreignWindow.show(root: UIViewController())
        foreignWindow.addSubview(root.view)

        let result = WindowUIContextProviderImpl(window: selectedWindow).current()

        guard case .windowOnly(let resolvedWindow) = result else {
            Issue.record("Expected a foreign-window root controller to be rejected")
            return
        }
        #expect(resolvedWindow === selectedWindow)
    }

    @Test func `Presented controller mounted in another window is skipped`() {
        let selectedWindow = TestWindow()
        let foreignWindow = TestWindow()
        defer {
            selectedWindow.close()
            foreignWindow.close()
        }

        let root = PresentingViewController()
        let foreignChild = UIViewController()
        root.presentedOverride = foreignChild
        selectedWindow.show(root: root)
        foreignWindow.show(root: UIViewController())
        foreignWindow.addSubview(foreignChild.view)

        let result = WindowUIContextProviderImpl(window: selectedWindow).current()

        guard case .windowAndController(_, let controller) = result else {
            Issue.record("Expected the coherent root controller to remain available")
            return
        }
        #expect(controller === root)
    }

    @Test func `Resolver terminates safely when presentation chain cycles`() {
        let window = TestWindow()
        let root = PresentingViewController()
        defer {
            root.presentedOverride = nil
            window.close()
        }
        window.show(root: root)
        root.presentedOverride = root

        let result = WindowUIContextProviderImpl(window: window).current()

        guard case .windowAndController(_, let controller) = result else {
            Issue.record("Expected the coherent root controller to remain available")
            return
        }
        #expect(controller === root)
    }

    @Test func `Window without a root controller resolves as window only`() {
        let window = TestWindow()
        defer { window.close() }

        let result = WindowUIContextProviderImpl(window: window).current()

        guard case .windowOnly(let resolvedWindow) = result else {
            Issue.record("Expected a rootless window to resolve without a controller")
            return
        }
        #expect(resolvedWindow === window)
    }

    @Test func `Window bound provider never substitutes another window`() throws {
        let expectedWindow = TestWindow()
        let otherWindow = TestWindow()
        defer {
            expectedWindow.close()
            otherWindow.close()
        }
        expectedWindow.show(root: UIViewController())
        otherWindow.show(root: UIViewController())

        let provider = WindowUIContextProviderImpl(window: expectedWindow)

        guard case .windowAndController(let resolvedWindow, _) = provider.current() else {
            Issue.record("Expected the bound window to resolve")
            return
        }
        #expect(resolvedWindow === expectedWindow)
        #expect(resolvedWindow !== otherWindow)
    }

    @Test func `Window bound provider reports owner closed after the window is released`() throws {
        let provider: WindowUIContextProviderImpl
        weak var weakWindow: UIWindow?
        do {
            let window = TestWindow()
            weakWindow = window
            provider = WindowUIContextProviderImpl(window: window)
        }

        #expect(weakWindow == nil)
        guard case .failure(let error) = provider.current() else {
            Issue.record("Expected a released bound window to fail resolution")
            return
        }
        let resolutionError = try #require(error as? UIContextResolutionError)
        #expect(resolutionError.reason == .ownerClosed)
    }

    @Test func `Resolution error preserves reason message and cause`() {
        let cause = ContextTestError()
        let error = UIContextResolutionError(
            reason: .unavailable,
            message: "No eligible window",
            cause: cause
        )

        #expect(error.reason == .unavailable)
        #expect(error.message == "No eligible window")
        #expect(error.cause as? ContextTestError == cause)
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

    func showWithoutMakingKey(root: UIViewController) {
        rootViewController = root
        isHidden = false
        root.view.frame = bounds
        root.view.layoutIfNeeded()
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

private struct ContextTestError: Error, Equatable, LocalizedError {
    var errorDescription: String? { "Context test cause" }
}
