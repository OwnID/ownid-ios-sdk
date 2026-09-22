@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI
import UIKit

internal protocol BottomSheetPresenter: Sendable {
    @MainActor
    func show<Content: View>(
        themeStore: OwnIDThemeStore,
        onFailure: @escaping @MainActor (BottomSheetPresentationError) -> Void,
        content: @MainActor (OwnIDUIContainerController) -> Content
    ) throws
}

internal enum BottomSheetPresentationError: String, LocalizedError, Sendable {
    case launchAlreadyInProgress
    case missingPresentationController
    case hostNotReady
    case containerClosedBeforePresentation
    case presentationAcknowledgementTimedOut

    internal var errorDescription: String? {
        switch self {
        case .launchAlreadyInProgress:
            return "Launch already in progress"
        case .missingPresentationController:
            return "UI context does not include a presentation controller"
        case .hostNotReady:
            return "Host is transitioning or off-screen"
        case .containerClosedBeforePresentation:
            return "Operation container closed before presentation"
        case .presentationAcknowledgementTimedOut:
            return "Bottom sheet presentation acknowledgement timed out after 3 seconds"
        }
    }
}

internal final class BottomSheetPresenterImpl: BottomSheetPresenter, @unchecked Sendable {
    private enum TimingConstants {
        static let watchdogDelayNs: UInt64 = 3_000_000_000
        static let retryDelayNs: UInt64 = 160_000_000
        static let presentationAttemptCount = 4
    }

    @MainActor
    private final class ActivePresentation {
        private let presenterRetainer: BottomSheetPresenterImpl
        weak var window: UIWindow?
        weak var scene: UIWindowScene?
        let usesLegacyScene: Bool
        let containerController: OwnIDUIContainerController
        let viewController: BottomSheetViewController
        let onFailure: @MainActor (BottomSheetPresentationError) -> Void

        var presentLoopTask: Task<Void, Never>?
        var presentWatchdog: Task<Void, Never>?
        var hasStartedPresentation = false
        var hasAcknowledgedUIKitPresentation = false

        init(
            presenter: BottomSheetPresenterImpl,
            window: UIWindow,
            containerController: OwnIDUIContainerController,
            themeStore: OwnIDThemeStore,
            content: AnyView,
            onFailure: @escaping @MainActor (BottomSheetPresentationError) -> Void
        ) {
            self.presenterRetainer = presenter
            self.window = window
            self.scene = window.windowScene
            self.usesLegacyScene = window.windowScene == nil
            self.containerController = containerController
            self.viewController = BottomSheetViewController(
                expectedWindow: window,
                containerController: containerController,
                themeStore: themeStore,
                content: content
            )
            self.onFailure = onFailure
        }

        func cancelTransientTasks() {
            presentLoopTask?.cancel()
            presentLoopTask = nil
            presentWatchdog?.cancel()
            presentWatchdog = nil
        }
    }

    private let uiContextProvider: any UIContextProvider
    private let logger: OwnIDLogRouter?

    @MainActor private var activePresentation: ActivePresentation?

    internal init(uiContextProvider: any UIContextProvider, logger: OwnIDLogRouter?) {
        self.uiContextProvider = uiContextProvider
        self.logger = logger
    }

    @MainActor
    internal func show<Content: View>(
        themeStore: OwnIDThemeStore,
        onFailure: @escaping @MainActor (BottomSheetPresentationError) -> Void,
        content: @MainActor (OwnIDUIContainerController) -> Content
    ) throws {
        guard activePresentation == nil else {
            throw BottomSheetPresentationError.launchAlreadyInProgress
        }

        let window: UIWindow
        switch uiContextProvider.current() {
        case .windowAndController(let resolvedWindow, _):
            window = resolvedWindow
        case .windowOnly:
            throw BottomSheetPresentationError.missingPresentationController
        case .failure(let error):
            throw error
        }

        let containerController = OwnIDUIContainerController { [weak self] in
            self?.dismissActivePresentation()
        }
        let resolvedContent = AnyView(content(containerController))
        guard !containerController.isClosing else {
            throw BottomSheetPresentationError.containerClosedBeforePresentation
        }

        let presentation = ActivePresentation(
            presenter: self,
            window: window,
            containerController: containerController,
            themeStore: themeStore,
            content: resolvedContent,
            onFailure: onFailure
        )

        presentation.viewController.onUIKitPresentationAcknowledged = { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            self.acknowledgeUIKitPresentation(presentation)
        }
        containerController.addClosedHandler { [weak self, weak presentation] _ in
            guard let self, let presentation else { return }
            guard presentation === self.activePresentation else { return }
            presentation.cancelTransientTasks()
            self.activePresentation = nil
        }

        activePresentation = presentation
        presentation.presentLoopTask = Task { @MainActor [weak self, weak presentation] in
            guard let self, let presentation else { return }
            for attempt in 0..<TimingConstants.presentationAttemptCount {
                if attempt > 0 {
                    do {
                        try await Task.sleep(nanoseconds: TimingConstants.retryDelayNs)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled, presentation === self.activePresentation else { return }
                guard !presentation.containerController.isClosing else { return }

                switch self.uiContextProvider.current() {
                case .windowAndController(let resolvedWindow, let host):
                    guard self.matchesInitialOwner(window: resolvedWindow, presentation: presentation) else {
                        self.failPresentation(presentation: presentation, error: .hostNotReady)
                        return
                    }
                    guard self.isReadyToPresent(on: host, in: resolvedWindow) else { continue }
                    self.presentOnHost(host: host, presentation: presentation)
                    return
                case .windowOnly:
                    self.failPresentation(presentation: presentation, error: .hostNotReady)
                    return
                case .failure(let error):
                    self.logger?.logW(
                        source: self,
                        prefix: "show",
                        message: "UI context resolution failed during presentation retry",
                        cause: error
                    )
                    self.failPresentation(presentation: presentation, error: .hostNotReady)
                    return
                }
            }
            self.failPresentation(presentation: presentation, error: .hostNotReady)
        }
    }

    @MainActor
    private func dismissActivePresentation() {
        guard let activePresentation else { return }
        dismiss(activePresentation)
    }

    @MainActor
    private func dismiss(_ presentation: ActivePresentation) {
        guard presentation === activePresentation else { return }

        logger?.logD(source: self, prefix: #function, message: "Dismiss requested")

        presentation.cancelTransientTasks()

        guard presentation.hasStartedPresentation else {
            presentation.containerController.markClosed()
            return
        }

        presentation.viewController.requestDismiss { [weak presentation] in
            presentation?.containerController.markClosed()
        }
    }

    @MainActor
    private func isReadyToPresent(on host: UIViewController, in window: UIWindow) -> Bool {
        var candidate: UIViewController? = host
        while let current = candidate {
            guard !(current is BottomSheetViewController) else { return false }
            candidate = current.parent ?? current.presentingViewController
        }
        guard !window.isHidden, window.alpha > 0 else { return false }
        if let scene = window.windowScene {
            guard scene.activationState == .foregroundActive else { return false }
        } else {
            guard UIContextLifecycleMode.isLegacy() else { return false }
            guard UIApplication.shared.applicationState == .active else { return false }
        }
        guard let view = host.viewIfLoaded, view.window === window, !view.isHidden, view.alpha > 0 else { return false }
        guard !host.isMovingToParent, !host.isMovingFromParent else { return false }
        guard !host.isBeingPresented, !host.isBeingDismissed, host.transitionCoordinator == nil else { return false }
        return host.presentedViewController == nil
    }

    @MainActor
    private func acknowledgeUIKitPresentation(_ presentation: ActivePresentation) {
        guard presentation === activePresentation else { return }
        guard !presentation.hasAcknowledgedUIKitPresentation else { return }
        guard let window = presentation.window, presentation.viewController.viewIfLoaded?.window === window else { return }
        presentation.hasAcknowledgedUIKitPresentation = true
        presentation.presentWatchdog?.cancel()
        presentation.presentWatchdog = nil
    }

    @MainActor
    private func presentOnHost(host: UIViewController, presentation: ActivePresentation) {
        guard presentation === activePresentation else { return }
        guard !presentation.containerController.isClosing else { return }

        presentation.hasStartedPresentation = true
        presentation.viewController.beginPresentationLifecycle()
        logger?.logD(source: self, prefix: "presentOnHost", message: "Presenting bottom sheet")
        presentation.presentWatchdog?.cancel()
        presentation.presentWatchdog = Task { @MainActor [weak self, weak presentation] in
            do {
                try await Task.sleep(nanoseconds: TimingConstants.watchdogDelayNs)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard let presentation else { return }
            guard presentation === self.activePresentation else { return }
            guard !presentation.hasAcknowledgedUIKitPresentation, !presentation.containerController.isClosing else { return }
            self.failPresentation(
                presentation: presentation,
                error: .presentationAcknowledgementTimedOut
            )
        }

        if #unavailable(iOS 15.0) {
            host.view.window?.endEditing(true)
        }

        host.present(presentation.viewController, animated: false) { [weak presentation] in
            presentation?.viewController.acknowledgeUIKitPresentation()
        }
    }

    @MainActor
    private func matchesInitialOwner(window: UIWindow, presentation: ActivePresentation) -> Bool {
        guard let initialWindow = presentation.window, window === initialWindow else { return false }
        if presentation.usesLegacyScene {
            return window.windowScene == nil
        }
        guard let initialScene = presentation.scene else { return false }
        return window.windowScene === initialScene
    }

    @MainActor
    private func failPresentation(presentation: ActivePresentation, error: BottomSheetPresentationError) {
        guard presentation === activePresentation else { return }
        presentation.cancelTransientTasks()
        presentation.containerController.requestDismissWithoutAbort()
        presentation.onFailure(error)
    }
}
