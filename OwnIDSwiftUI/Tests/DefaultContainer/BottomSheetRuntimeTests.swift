import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
struct BottomSheetRuntimeTests {

    @Test func `View controller exposes modal accessibility and escape closes container`() {
        var closeActionCount = 0
        let containerController = OwnIDUIContainerController {
            closeActionCount += 1
        }
        let viewController = bottomSheetViewController(containerController: containerController)

        viewController.loadViewIfNeeded()
        let overlay = viewController.view.subviews.compactMap { $0 as? UIControl }.first

        #expect(viewController.modalPresentationStyle == .overFullScreen)
        #expect(viewController.view.accessibilityViewIsModal)
        #expect(overlay?.isAccessibilityElement == false)
        #expect(overlay?.accessibilityElementsHidden == true)
        #expect(viewController.accessibilityPerformEscape())
        #expect(containerController.isClosing)
        #expect(closeActionCount == 1)
    }

    @Test func `Unexpected disappearance closes container and reports lifecycle callback`() {
        var unexpectedDisappearCount = 0
        var closedReasons: [String?] = []
        let containerController = OwnIDUIContainerController(closeAction: {})
        let viewController = bottomSheetViewController(containerController: containerController)
        viewController.onDidDisappearUnexpectedly = {
            unexpectedDisappearCount += 1
        }
        containerController.addClosedHandler { reason in
            closedReasons.append(reason?.description)
        }

        viewController.loadViewIfNeeded()
        viewController.beginAppearanceTransition(true, animated: false)
        viewController.endAppearanceTransition()
        viewController.beginAppearanceTransition(false, animated: false)
        viewController.endAppearanceTransition()

        #expect(unexpectedDisappearCount == 1)
        #expect(containerController.isClosed)
        #expect(closedReasons == [Reason.userClose(details: "Operation container closed").description])
    }

    @Test func `Expected dismiss closes container without unexpected disappearance callback`() async {
        var unexpectedDisappearCount = 0
        var dismissCompletionCount = 0
        var closedReasons: [String?] = []
        let containerController = OwnIDUIContainerController(closeAction: {})
        let viewController = bottomSheetViewController(containerController: containerController)
        viewController.onDidDisappearUnexpectedly = {
            unexpectedDisappearCount += 1
        }
        containerController.addClosedHandler { reason in
            closedReasons.append(reason?.description)
        }

        viewController.loadViewIfNeeded()
        viewController.requestDismiss {
            dismissCompletionCount += 1
            containerController.markClosed()
        }
        await Task.yield()

        #expect(dismissCompletionCount == 1)
        #expect(unexpectedDisappearCount == 0)
        #expect(containerController.isClosed)
        #expect(closedReasons == [Reason.userClose(details: "Operation container closed").description])
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Presenter rejects duplicate launch and reports missing host`() async throws {
        let uiContextProvider = BottomSheetTestUIContextProvider(hosts: [nil, nil, nil, nil])
        let presenter = BottomSheetPresenterImpl(uiContextProvider: uiContextProvider, logger: nil)
        let failures = BottomSheetFailureProbe()

        presenter.show(
            themeStore: OwnIDThemeStore(),
            onFailure: { reason in Task { await failures.record(reason) } }
        ) { _ in
            Text("First")
        }
        presenter.show(
            themeStore: OwnIDThemeStore(),
            onFailure: { reason in Task { await failures.record(reason) } }
        ) { _ in
            Text("Second")
        }

        let duplicateFailure = await failures.next()
        let missingHostFailure = await failures.next()

        #expect(duplicateFailure.description == Reason.systemError(details: "Launch already in progress").description)
        #expect(missingHostFailure.description == Reason.systemError(details: "Top view controller not found").description)
        #expect(uiContextProvider.topMostViewControllerCallCount == 4)
    }

    private func bottomSheetViewController(
        containerController: OwnIDUIContainerController
    ) -> BottomSheetViewController {
        BottomSheetViewController(
            content: AnyView(Text("Sheet content")),
            themeStore: OwnIDThemeStore(),
            containerController: containerController
        )
    }
}

@MainActor
private final class BottomSheetTestUIContextProvider: UIContextProvider, @unchecked Sendable {
    private let hosts: [UIViewController?]
    private(set) var topMostViewControllerCallCount = 0

    init(hosts: [UIViewController?]) {
        self.hosts = hosts
    }

    func activeWindow() -> UIWindow? {
        nil
    }

    func topMostViewController(_ window: UIWindow?) -> UIViewController? {
        defer { topMostViewControllerCallCount += 1 }
        guard topMostViewControllerCallCount < hosts.count else {
            return hosts.last ?? nil
        }
        return hosts[topMostViewControllerCallCount]
    }
}

private actor BottomSheetFailureProbe {
    private var values: [Reason] = []
    private var waiters: [CheckedContinuation<Reason, Never>] = []

    func record(_ reason: Reason) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: reason)
        } else {
            values.append(reason)
        }
    }

    func next() async -> Reason {
        if !values.isEmpty {
            return values.removeFirst()
        }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
