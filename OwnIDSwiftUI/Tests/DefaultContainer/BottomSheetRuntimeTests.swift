import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
// Covers: UI-PRESENT-160, UI-PRESENT-240, UI-PRESENT-290
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

    @Test func `Overlay tap closes container through synthetic control event`() throws {
        var closeActionCount = 0
        let containerController = OwnIDUIContainerController {
            closeActionCount += 1
        }
        let viewController = bottomSheetViewController(containerController: containerController)

        viewController.loadViewIfNeeded()
        let overlay = try #require(viewController.view.subviews.compactMap { $0 as? UIControl }.first)
        try activate(overlay, for: .touchUpInside)
        try activate(overlay, for: .touchUpInside)

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

        let duplicateFailure = try await failures.next("duplicate launch failure")
        let missingHostFailure = try await failures.next("missing host failure")

        #expect(duplicateFailure.description == Reason.systemError(details: "Launch already in progress").description)
        #expect(missingHostFailure.description == Reason.systemError(details: "Top view controller not found").description)
        #expect(uiContextProvider.topMostViewControllerCallCount > 0)
    }

    @available(iOS 16.0, *)
    @Test(.serialized, .timeLimit(.minutes(1)), arguments: BottomSheetOffscreenHostVariant.allCases)
    private func `Presenter rejects host variants that are offscreen or dismissing`(_ variant: BottomSheetOffscreenHostVariant)
        async throws
    {
        let expectedFailure = Reason.systemError(details: "Host is dismissing or off-screen").description
        let host = variant.makeHost()
        defer { host.close() }
        let hosts = Array<UIViewController?>(repeating: host.viewController, count: 4)
        let uiContextProvider = BottomSheetTestUIContextProvider(hosts: hosts)
        let presenter = BottomSheetPresenterImpl(uiContextProvider: uiContextProvider, logger: nil)
        let failures = BottomSheetFailureProbe()

        presenter.show(
            themeStore: OwnIDThemeStore(),
            onFailure: { reason in Task { await failures.record(reason) } }
        ) { _ in
            Text("Sheet")
        }

        let failure = try await failures.next("bottom sheet failure for \(variant.testDescription)")

        #expect(failure.description == expectedFailure)
        #expect(uiContextProvider.topMostViewControllerCallCount > 0)
    }

    @Test func `Layout metrics resolve keyboard overlap and top`() {
        let viewBounds = CGRect(x: 0, y: 0, width: 320, height: 640)

        #expect(
            BottomSheetLayoutMetrics.keyboardOverlap(
                viewBounds: viewBounds,
                keyboardFrameInView: CGRect(x: 0, y: 420, width: 320, height: 300)
            ) == 220
        )
        #expect(
            BottomSheetLayoutMetrics.keyboardOverlap(
                viewBounds: viewBounds,
                keyboardFrameInView: CGRect(x: 0, y: 700, width: 320, height: 100)
            ) == 0
        )

        #expect(BottomSheetLayoutMetrics.keyboardTop(viewHeight: 640, layoutGuideMinY: 0) == 640)
        #expect(BottomSheetLayoutMetrics.keyboardTop(viewHeight: 640, layoutGuideMinY: 420) == 420)
        #expect(BottomSheetLayoutMetrics.keyboardTop(viewHeight: 640, keyboardOverlap: 220) == 420)
        #expect(BottomSheetLayoutMetrics.keyboardTop(viewHeight: 100, keyboardOverlap: 180) == 0)
    }

    @Test func `Layout metrics cap sheet size and fitting dimensions`() {
        #expect(BottomSheetLayoutMetrics.maxSheetHeight(viewHeight: 640, safeAreaTop: 44, keyboardTop: 420) == 376)
        #expect(BottomSheetLayoutMetrics.maxSheetHeight(viewHeight: 640, safeAreaTop: 44, keyboardTop: 0) == 596)
        #expect(BottomSheetLayoutMetrics.maxSheetHeight(viewHeight: 640, safeAreaTop: 44, keyboardOverlap: 220) == 376)
        #expect(BottomSheetLayoutMetrics.maxSheetHeight(viewHeight: 40, safeAreaTop: 80, keyboardOverlap: 20) == 1)

        #expect(BottomSheetLayoutMetrics.sheetFittingWidth(containerWidth: 300, viewWidth: 360, maxSheetWidth: 480) == 300)
        #expect(BottomSheetLayoutMetrics.sheetFittingWidth(containerWidth: 0, viewWidth: 600, maxSheetWidth: 480) == 480)
        #expect(BottomSheetLayoutMetrics.resolvedSheetHeight(fittingHeight: 120.2, maxSheetHeight: 400) == 121)
        #expect(BottomSheetLayoutMetrics.resolvedSheetHeight(fittingHeight: 500, maxSheetHeight: 400) == 400)
        #expect(BottomSheetLayoutMetrics.resolvedSheetHeight(fittingHeight: 0, maxSheetHeight: 400) == 1)
    }

    @Test func `Layout metrics resolve keyboard-visible drag and dismissal offsets`() {
        #expect(BottomSheetLayoutMetrics.isKeyboardVisible(currentKeyboardTop: 420, viewHeight: 640, safeAreaBottom: 34))
        #expect(BottomSheetLayoutMetrics.isKeyboardVisible(currentKeyboardTop: 640, viewHeight: 640, safeAreaBottom: 34) == false)

        #expect(
            BottomSheetLayoutMetrics.interactiveDismissOffset(
                proposedOffset: 300,
                isKeyboardVisible: true,
                panStartTouchY: 300,
                currentKeyboardTop: 420
            ) == 119
        )
        #expect(
            BottomSheetLayoutMetrics.interactiveDismissOffset(
                proposedOffset: 300,
                isKeyboardVisible: false,
                panStartTouchY: 300,
                currentKeyboardTop: 420
            ) == 300
        )
        #expect(
            BottomSheetLayoutMetrics.interactiveDismissOffset(
                proposedOffset: 300,
                isKeyboardVisible: true,
                panStartTouchY: nil,
                currentKeyboardTop: 420
            ) == 300
        )

        #expect(BottomSheetLayoutMetrics.dismissedTranslationY(sheetHeight: 200, safeAreaBottom: 34) == 258)
        #expect(BottomSheetLayoutMetrics.dismissedTranslationY(sheetHeight: 0, safeAreaBottom: 34) == 59)
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

private enum BottomSheetOffscreenHostVariant: CaseIterable, CustomTestStringConvertible {
    case missingWindow
    case dismissingHost
    case dismissingPresentedController

    var testDescription: String {
        switch self {
        case .missingWindow:
            "missing window"
        case .dismissingHost:
            "dismissing host"
        case .dismissingPresentedController:
            "dismissing presented controller"
        }
    }

    @MainActor
    func makeHost() -> BottomSheetOffscreenHost {
        switch self {
        case .missingWindow:
            BottomSheetOffscreenHost.missingWindow()
        case .dismissingHost:
            BottomSheetOffscreenHost.dismissingHost()
        case .dismissingPresentedController:
            BottomSheetOffscreenHost.dismissingPresentedController()
        }
    }
}

@MainActor
private struct BottomSheetOffscreenHost {
    let viewController: UIViewController
    private let window: UIKitRuntimeTestWindow?

    static func missingWindow() -> Self {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        return Self(viewController: viewController, window: nil)
    }

    static func dismissingHost() -> Self {
        let viewController = BottomSheetDismissingViewController()
        let window = UIKitRuntimeTestWindow()
        window.show(root: viewController)
        return Self(viewController: viewController, window: window)
    }

    static func dismissingPresentedController() -> Self {
        let viewController = BottomSheetPresentingViewController()
        viewController.presentedOverride = BottomSheetDismissingViewController()
        let window = UIKitRuntimeTestWindow()
        window.show(root: viewController)
        return Self(viewController: viewController, window: window)
    }

    func close() {
        window?.close()
    }
}

private final class BottomSheetDismissingViewController: UIViewController {
    override var isBeingDismissed: Bool { true }
}

private final class BottomSheetPresentingViewController: UIViewController {
    var presentedOverride: UIViewController?

    override var presentedViewController: UIViewController? {
        presentedOverride ?? super.presentedViewController
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

    func next(_ description: String, seconds: UInt64 = 5) async throws -> Reason {
        try await withBottomSheetRuntimeTimeout(description, seconds: seconds) {
            await self.next()
        }
    }

    private func next() async -> Reason {
        if !values.isEmpty {
            return values.removeFirst()
        }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

private enum BottomSheetRuntimeTimeoutError: Error {
    case timedOut(String)
}

private func withBottomSheetRuntimeTimeout<T: Sendable>(
    _ description: String,
    seconds: UInt64 = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        defer { group.cancelAll() }
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw BottomSheetRuntimeTimeoutError.timedOut(description)
        }
        return try await group.next()!
    }
}
