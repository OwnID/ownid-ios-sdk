import Testing
import UIKit

@MainActor
final class UIKitRuntimeTestWindow: UIWindow {
    init(size: CGSize = CGSize(width: 320, height: 640)) {
        super.init(frame: CGRect(origin: .zero, size: size))
        windowLevel = .normal
    }

    override var canBecomeKey: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
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

@MainActor
final class UIKitViewControllerRuntimeHost: SwiftUIRuntimeSettlingHost {
    private let window: UIKitRuntimeTestWindow
    private let rootViewController = UIViewController()
    private let viewController: UIViewController

    init(viewController: UIViewController, size: CGSize = CGSize(width: 320, height: 480)) {
        self.viewController = viewController
        self.window = UIKitRuntimeTestWindow(size: size)

        window.show(root: rootViewController)
        rootViewController.addChild(viewController)
        rootViewController.view.addSubview(viewController.view)
        viewController.view.frame = rootViewController.view.bounds
        viewController.didMove(toParent: rootViewController)

        layout()
    }

    func settle(cycles: Int = 4) async {
        for _ in 0..<cycles {
            await Task.yield()
            layout()
        }
    }

    func layout() {
        rootViewController.view.setNeedsLayout()
        rootViewController.view.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
    }

    func close() {
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
        window.close()
    }
}

@MainActor
func activate(_ control: UIControl, for event: UIControl.Event) throws {
    var didActivate = false
    for target in control.allTargets {
        let targetObject = try #require(target.base as? NSObject)
        for action in control.actions(forTarget: targetObject, forControlEvent: event) ?? [] {
            didActivate = true
            _ = targetObject.perform(Selector(action))
        }
    }
    #expect(didActivate)
}
