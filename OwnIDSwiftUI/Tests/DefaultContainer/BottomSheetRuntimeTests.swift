import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
// Covers: UI-PRESENT-160, UI-PRESENT-240, UI-PRESENT-290
struct BottomSheetRuntimeTests {

    @Test func `Completed entrance makes the sheet ready for input`() async throws {
        let containerController = OwnIDUIContainerController(closeAction: {})
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let viewController = bottomSheetViewController(containerController: containerController, expectedWindow: window)
        try attachForAppearanceCallbacks(viewController, in: window)
        try #require(UIApplication.shared.applicationState == .active)
        try #require(!containerController.isInputReady)
        try await waitForInputReadiness(containerController)

        #expect(containerController.isInputReady)
    }

    @Test func `Scene deactivation suppresses input and activation restores it`() async throws {
        let containerController = OwnIDUIContainerController(closeAction: {})
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let viewController = bottomSheetViewController(containerController: containerController, expectedWindow: window)
        try attachForAppearanceCallbacks(viewController, in: window)
        try #require(UIApplication.shared.applicationState == .active)

        try await waitForInputReadiness(containerController)
        let scene = try #require(window.windowScene)

        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        try await waitForInputReadiness(containerController, expected: false)

        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        try await waitForInputReadiness(containerController)
    }

    @Test func `Closing before entrance completion keeps input unavailable`() async throws {
        let containerController = OwnIDUIContainerController(closeAction: {})
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let viewController = bottomSheetViewController(containerController: containerController, expectedWindow: window)
        try attachForAppearanceCallbacks(viewController, in: window)
        try #require(UIApplication.shared.applicationState == .active)

        containerController.close()
        viewController.requestDismiss { containerController.markClosed() }
        try await waitForInputReadiness(containerController, expected: false)

        #expect(containerController.isClosing)
    }

    @Test func `Close during presenter entrance cancels watchdog without failure`() async throws {
        let host = BottomSheetCapturingHost()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        window.show(root: host)
        try #require(UIApplication.shared.applicationState == .active)
        let presenter = BottomSheetPresenterImpl(
            uiContextProvider: BottomSheetTestUIContextProvider(results: [.windowAndController(window: window, controller: host)]),
            logger: nil
        )
        var failures: [BottomSheetPresentationError] = []
        var container: OwnIDUIContainerController?
        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { controller in
            container = controller
            return Text("Sheet")
        }
        await Task.yield()
        let sheet = try #require(host.sheet)
        host.addChild(sheet)
        host.view.addSubview(sheet.view)
        sheet.didMove(toParent: host)
        sheet.beginAppearanceTransition(true, animated: false)
        sheet.endAppearanceTransition()

        container?.close()
        try await Task.sleep(nanoseconds: 3_200_000_000)

        #expect(failures.isEmpty)
        #expect(container?.isInputReady == false)
        #expect(container?.isClosing == true)
        container?.markClosed()
    }

    private func attachForAppearanceCallbacks(_ viewController: BottomSheetViewController, in window: UIKitRuntimeTestWindow) throws {
        let host = UIViewController()
        window.show(root: host)
        host.present(viewController, animated: false)
        try #require(viewController.presentingViewController === host)
        // The package harness drives appearance explicitly; installed runtime tests own UIKit transition completion.
        host.view.addSubview(viewController.view)
        viewController.view.frame = host.view.bounds
        viewController.beginPresentationLifecycle()
        viewController.beginAppearanceTransition(true, animated: false)
        viewController.endAppearanceTransition()
    }

    @Test func `Presenter reports one failure after host readiness retries are exhausted`() async throws {
        let host = UIViewController()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let provider = BottomSheetTestUIContextProvider(
            results: [.windowAndController(window: window, controller: host)]
        )
        let presenter = BottomSheetPresenterImpl(uiContextProvider: provider, logger: nil)
        var failures: [BottomSheetPresentationError] = []
        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { _ in
            Text("Sheet")
        }

        try await waitForPresentationFailures(count: 1) { failures }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(failures == [.hostNotReady])
        #expect(provider.callCount == 5) // Initial owner pin plus four presentation attempts.
    }

    @Test func `Presenter retries with fresh context and presents when the original owner becomes ready`() async throws {
        let unavailableHost = UIViewController()
        let readyHost = BottomSheetCapturingHost()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        window.show(root: readyHost)
        let provider = BottomSheetTestUIContextProvider(
            results: [
                .windowAndController(window: window, controller: unavailableHost),
                .windowAndController(window: window, controller: unavailableHost),
                .windowAndController(window: window, controller: readyHost),
            ]
        )
        let presenter = BottomSheetPresenterImpl(uiContextProvider: provider, logger: nil)
        var failures: [BottomSheetPresentationError] = []
        var container: OwnIDUIContainerController?

        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { controller in
            container = controller
            return Text("Sheet")
        }
        try await waitForPresentedSheet(on: readyHost)

        #expect(failures.isEmpty)
        container?.close()
        container?.markClosed()
    }

    @Test func `Closing a pending presentation prevents late UIKit presentation`() async throws {
        let host = BottomSheetCapturingHost()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let presenter = BottomSheetPresenterImpl(
            uiContextProvider: BottomSheetTestUIContextProvider(
                results: [.windowAndController(window: window, controller: host)]
            ),
            logger: nil
        )
        var failures: [BottomSheetPresentationError] = []
        var container: OwnIDUIContainerController?

        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { controller in
            container = controller
            return Text("Sheet")
        }
        container?.close()
        window.show(root: host)
        try await Task.sleep(nanoseconds: 650_000_000)

        #expect(container?.isClosed == true)
        #expect(host.sheet == nil)
        #expect(failures.isEmpty)
    }

    @Test func `Presenter rejects a different window without migrating the pending presentation`() async throws {
        let firstHost = BottomSheetCapturingHost()
        let secondHost = BottomSheetCapturingHost()
        let firstWindow = makeBottomSheetTestWindow()
        let secondWindow = makeBottomSheetTestWindow()
        defer {
            firstWindow.close()
            secondWindow.close()
        }
        firstWindow.show(root: firstHost)
        secondWindow.show(root: secondHost)
        let presenter = BottomSheetPresenterImpl(
            uiContextProvider: BottomSheetTestUIContextProvider(
                results: [
                    .windowAndController(window: firstWindow, controller: firstHost),
                    .windowAndController(window: secondWindow, controller: secondHost),
                ]
            ),
            logger: nil
        )
        var failures: [BottomSheetPresentationError] = []

        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { _ in Text("Sheet") }
        try await waitForPresentationFailures(count: 1) { failures }

        #expect(failures == [.hostNotReady])
        #expect(firstHost.sheet == nil)
        #expect(secondHost.sheet == nil)
    }

    @Test func `Presenter does not nest a sheet under an existing SDK sheet`() async throws {
        let previousContainer = OwnIDUIContainerController(closeAction: {})
        let previousSheet = bottomSheetViewController(containerController: previousContainer)
        let host = BottomSheetCapturingHost()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        window.show(root: previousSheet)
        previousSheet.addChild(host)
        previousSheet.view.addSubview(host.view)
        host.didMove(toParent: previousSheet)
        let presenter = BottomSheetPresenterImpl(
            uiContextProvider: BottomSheetTestUIContextProvider(
                results: [.windowAndController(window: window, controller: host)]
            ),
            logger: nil
        )
        var failures: [BottomSheetPresentationError] = []

        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { _ in Text("Sheet") }
        try await waitForPresentationFailures(count: 1) { failures }

        #expect(failures == [.hostNotReady])
        #expect(host.sheet == nil)
    }

    @Test func `Presenter succeeds when the previous SDK sheet disappears between retries`() async throws {
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let previousSheet = bottomSheetViewController(
            containerController: OwnIDUIContainerController(closeAction: {}),
            expectedWindow: window
        )
        let host = BottomSheetCapturingHost()
        window.show(root: previousSheet)
        previousSheet.addChild(host)
        previousSheet.view.addSubview(host.view)
        host.didMove(toParent: previousSheet)
        let provider = BottomSheetTestUIContextProvider(
            results: [.windowAndController(window: window, controller: host)]
        )
        let presenter = BottomSheetPresenterImpl(uiContextProvider: provider, logger: nil)
        var container: OwnIDUIContainerController?

        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { _ in }) { controller in
            container = controller
            return Text("Sheet")
        }
        for _ in 0..<100 where provider.callCount < 2 { await Task.yield() }
        try #require(provider.callCount >= 2)
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        window.show(root: host)
        try await waitForPresentedSheet(on: host)

        #expect(host.sheet != nil)
        container?.close()
        container?.markClosed()
    }

    @Test func `Window-only context throws without invoking the failure callback`() throws {
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        let provider = BottomSheetTestUIContextProvider(results: [.windowOnly(window)])
        let presenter = BottomSheetPresenterImpl(uiContextProvider: provider, logger: nil)
        var failureCount = 0

        do {
            try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { _ in failureCount += 1 }) { _ in
                Text("Sheet")
            }
            Issue.record("Expected a missing-presentation-controller error")
        } catch let error as BottomSheetPresentationError {
            #expect(error.rawValue == BottomSheetPresentationError.missingPresentationController.rawValue)
        } catch {
            Issue.record("Unexpected presentation error: \(error)")
        }
        #expect(failureCount == 0)
    }

    @Test func `UI context resolution errors propagate without invoking the failure callback`() throws {
        let resolutionError = UIContextResolutionError(
            reason: .ownerClosed,
            message: "The WebBridge owner is no longer attached."
        )
        let presenter = BottomSheetPresenterImpl(
            uiContextProvider: BottomSheetTestUIContextProvider(results: [.failure(resolutionError)]),
            logger: nil
        )
        var failureCount = 0

        do {
            try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { _ in failureCount += 1 }) { _ in
                Text("Sheet")
            }
            Issue.record("Expected the provider resolution error")
        } catch let error as UIContextResolutionError {
            #expect(error.reason == .ownerClosed)
            #expect(error.message == "The WebBridge owner is no longer attached.")
        } catch {
            Issue.record("Unexpected context resolution error: \(error)")
        }
        #expect(failureCount == 0)
    }

    @Test func `UIKit completion without expected-window attachment fails once and ignores late acknowledgement`() async throws {
        let host = BottomSheetCapturingHost()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        window.show(root: host)
        let presenter = BottomSheetPresenterImpl(
            uiContextProvider: BottomSheetTestUIContextProvider(
                results: [.windowAndController(window: window, controller: host)]
            ),
            logger: nil
        )
        var failures: [BottomSheetPresentationError] = []
        var closedReasons: [String?] = []
        var container: OwnIDUIContainerController?
        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { controller in
            container = controller
            controller.addClosedHandler { reason in closedReasons.append(reason?.description) }
            return Text("Sheet")
        }
        try await Task.sleep(nanoseconds: 3_200_000_000)

        let sheet = try #require(host.sheet)
        #expect(failures == [.presentationAcknowledgementTimedOut])
        #expect(container?.isClosing == true)
        #expect(container?.isClosed == true)
        #expect(closedReasons == [nil])

        sheet.acknowledgeUIKitPresentation()
        container?.close()
        container?.markClosed()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(failures == [.presentationAcknowledgementTimedOut])
        #expect(closedReasons == [nil])
    }

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

    @Test func `Unexpected disappearance closes container and reports user close`() {
        var closedReasons: [String?] = []
        let containerController = OwnIDUIContainerController(closeAction: {})
        let viewController = bottomSheetViewController(containerController: containerController)
        containerController.addClosedHandler { reason in
            closedReasons.append(reason?.description)
        }

        viewController.loadViewIfNeeded()
        viewController.beginAppearanceTransition(true, animated: false)
        viewController.endAppearanceTransition()
        viewController.beginAppearanceTransition(false, animated: false)
        viewController.endAppearanceTransition()

        #expect(containerController.isClosed)
        #expect(closedReasons == [Reason.userClose(details: "Operation container closed").description])
    }

    @Test func `Presenter throws for duplicate launch and missing presentation controller`() throws {
        let host = BottomSheetCapturingHost()
        let window = makeBottomSheetTestWindow()
        defer { window.close() }
        window.show(root: host)
        let uiContextProvider = BottomSheetTestUIContextProvider(
            results: [.windowAndController(window: window, controller: host)]
        )
        let presenter = BottomSheetPresenterImpl(uiContextProvider: uiContextProvider, logger: nil)
        var container: OwnIDUIContainerController?

        try presenter.show(
            themeStore: OwnIDThemeStore(),
            onFailure: { _ in }
        ) { controller in
            container = controller
            return Text("First")
        }

        do {
            try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { _ in }) { _ in
                Text("Second")
            }
            Issue.record("Expected duplicate-launch error")
        } catch let error as BottomSheetPresentationError {
            #expect(error.rawValue == BottomSheetPresentationError.launchAlreadyInProgress.rawValue)
        } catch {
            Issue.record("Unexpected duplicate-launch error: \(error)")
        }

        container?.close()
        container?.markClosed()

        let missingProvider = BottomSheetTestUIContextProvider(results: [.windowOnly(window)])
        let missingPresenter = BottomSheetPresenterImpl(uiContextProvider: missingProvider, logger: nil)
        do {
            try missingPresenter.show(themeStore: OwnIDThemeStore(), onFailure: { _ in }) { _ in Text("Missing") }
            Issue.record("Expected missing-presentation-controller error")
        } catch let error as BottomSheetPresentationError {
            #expect(error.rawValue == BottomSheetPresentationError.missingPresentationController.rawValue)
        } catch {
            Issue.record("Unexpected missing-controller error: \(error)")
        }
    }

    @available(iOS 16.0, *)
    @Test(.serialized, .timeLimit(.minutes(1)), arguments: BottomSheetOffscreenHostVariant.allCases)
    private func `Presenter rejects host variants that are offscreen or dismissing`(_ variant: BottomSheetOffscreenHostVariant)
        async throws
    {
        let host = variant.makeHost()
        defer { host.close() }
        let uiContextProvider = BottomSheetTestUIContextProvider(results: [host.contextResult])
        let presenter = BottomSheetPresenterImpl(uiContextProvider: uiContextProvider, logger: nil)
        var failures: [BottomSheetPresentationError] = []

        try presenter.show(themeStore: OwnIDThemeStore(), onFailure: { failures.append($0) }) { _ in Text("Sheet") }
        try await waitForPresentationFailures(count: 1) { failures }

        #expect(failures == [.hostNotReady], "Unexpected host result for \(variant.testDescription)")
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
        containerController: OwnIDUIContainerController,
        expectedWindow: UIWindow? = nil
    ) -> BottomSheetViewController {
        let expectedWindow = expectedWindow ?? makeBottomSheetTestWindow()
        return BottomSheetViewController(
            expectedWindow: expectedWindow,
            containerController: containerController,
            themeStore: OwnIDThemeStore(),
            content: AnyView(Text("Sheet content"))
        )
    }
}

@MainActor
private func waitForInputReadiness(
    _ containerController: OwnIDUIContainerController,
    expected: Bool = true
) async throws {
    for _ in 0..<100 {
        if containerController.isInputReady == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    throw BottomSheetReadinessTimeout(expected: expected)
}

private struct BottomSheetReadinessTimeout: Error {
    let expected: Bool
}

@MainActor
private func waitForPresentationFailures(
    count: Int,
    observed: @MainActor () -> [BottomSheetPresentationError]
) async throws {
    for _ in 0..<100 where observed().count < count {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(observed().count == count)
}

@MainActor
private func waitForPresentedSheet(on host: BottomSheetCapturingHost) async throws {
    for _ in 0..<100 where host.sheet == nil {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try #require(host.sheet != nil)
}

@MainActor
private func makeBottomSheetTestWindow() -> UIKitRuntimeTestWindow {
    let window = UIKitRuntimeTestWindow()
    if let foregroundScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })
    {
        window.windowScene = foregroundScene
    }
    return window
}

private enum BottomSheetOffscreenHostVariant: CaseIterable, CustomTestStringConvertible {
    case missingWindow
    case dismissingHost
    case dismissingPresentedController
    case hiddenHost
    case transparentHost
    case presentingHost
    case movingHost
    case hiddenWindow
    case transparentWindow
    case occupiedHost

    var testDescription: String {
        switch self {
        case .missingWindow:
            "missing window"
        case .dismissingHost:
            "dismissing host"
        case .dismissingPresentedController:
            "dismissing presented controller"
        case .hiddenHost:
            "hidden host"
        case .transparentHost:
            "transparent host"
        case .presentingHost:
            "presenting host"
        case .movingHost:
            "moving host"
        case .hiddenWindow:
            "hidden window"
        case .transparentWindow:
            "transparent window"
        case .occupiedHost:
            "occupied host"
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
        case .hiddenHost, .transparentHost, .presentingHost, .movingHost, .hiddenWindow, .transparentWindow, .occupiedHost:
            BottomSheetOffscreenHost.unavailable(self)
        }
    }
}

@MainActor
private struct BottomSheetOffscreenHost {
    let viewController: UIViewController
    let window: UIKitRuntimeTestWindow?

    var contextResult: UIContextResult {
        if let window {
            return .windowAndController(window: window, controller: viewController)
        }
        return .windowAndController(window: makeBottomSheetTestWindow(), controller: viewController)
    }

    static func missingWindow() -> Self {
        let viewController = UIViewController()
        viewController.loadViewIfNeeded()
        return Self(viewController: viewController, window: nil)
    }

    static func dismissingHost() -> Self {
        let viewController = BottomSheetDismissingViewController()
        let window = makeBottomSheetTestWindow()
        window.show(root: viewController)
        return Self(viewController: viewController, window: window)
    }

    static func dismissingPresentedController() -> Self {
        let viewController = BottomSheetPresentingViewController()
        viewController.presentedOverride = BottomSheetDismissingViewController()
        let window = makeBottomSheetTestWindow()
        window.show(root: viewController)
        return Self(viewController: viewController, window: window)
    }

    static func unavailable(_ variant: BottomSheetOffscreenHostVariant) -> Self {
        let viewController: UIViewController
        switch variant {
        case .presentingHost: viewController = BottomSheetBeingPresentedHost()
        case .movingHost: viewController = BottomSheetMovingHost()
        case .occupiedHost:
            let host = BottomSheetPresentingViewController()
            host.presentedOverride = UIViewController()
            viewController = host
        default: viewController = UIViewController()
        }
        let window = makeBottomSheetTestWindow()
        window.show(root: viewController)
        if variant == .hiddenHost { viewController.view.isHidden = true }
        if variant == .transparentHost { viewController.view.alpha = 0 }
        if variant == .hiddenWindow { window.isHidden = true }
        if variant == .transparentWindow { window.alpha = 0 }
        return Self(viewController: viewController, window: window)
    }

    func close() {
        window?.close()
    }
}

private final class BottomSheetDismissingViewController: UIViewController {
    override var isBeingDismissed: Bool { true }
}

private final class BottomSheetBeingPresentedHost: UIViewController {
    override var isBeingPresented: Bool { true }
}

private final class BottomSheetMovingHost: UIViewController {
    override var isMovingFromParent: Bool { true }
}

private final class BottomSheetPresentingViewController: UIViewController {
    var presentedOverride: UIViewController?

    override var presentedViewController: UIViewController? {
        presentedOverride ?? super.presentedViewController
    }
}

private final class BottomSheetCapturingHost: UIViewController {
    var sheet: BottomSheetViewController?

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        sheet = viewControllerToPresent as? BottomSheetViewController
        completion?()
    }
}

@MainActor
private final class BottomSheetTestUIContextProvider: UIContextProvider, @unchecked Sendable {
    private let results: [UIContextResult]
    private var index = 0
    var callCount: Int { index }

    init(results: [UIContextResult]) {
        self.results = results
    }

    func current() -> UIContextResult {
        defer { index += 1 }
        guard index < results.count else { return results.last ?? .failure(TestUIContextError.missing) }
        return results[index]
    }
}

private enum TestUIContextError: Error {
    case missing
}
