@_spi(OwnIDInternal) import OwnIDCore
import SwiftUI
import UIKit

internal protocol BottomSheetPresenter: Sendable {
    @MainActor
    func show<Content: View>(
        themeStore: OwnIDThemeStore,
        onFailure: @escaping @MainActor (Reason) -> Void,
        content: @escaping @MainActor (OwnIDUIContainerController) -> Content
    )
}

internal final class BottomSheetPresenterImpl: BottomSheetPresenter, @unchecked Sendable {
    private enum TimingConstants {
        static let maxRetries = 3
        static let retryDelayNs: UInt64 = 160_000_000
        static let watchdogDelayNs: UInt64 = 3_000_000_000
    }

    @MainActor
    private final class ActivePresentation {
        private let presenterRetainer: BottomSheetPresenterImpl
        let containerController: OwnIDUIContainerController
        let viewController: BottomSheetViewController
        let onFailure: @MainActor (Reason) -> Void

        var presentLoopTask: Task<Void, Never>?
        var presentWatchdog: Task<Void, Never>?
        var hasStartedPresentation = false
        var hasOpened = false

        init(
            presenter: BottomSheetPresenterImpl,
            content: AnyView,
            themeStore: OwnIDThemeStore,
            containerController: OwnIDUIContainerController,
            onFailure: @escaping @MainActor (Reason) -> Void
        ) {
            self.presenterRetainer = presenter
            self.containerController = containerController
            self.viewController = BottomSheetViewController(
                content: content,
                themeStore: themeStore,
                containerController: containerController
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
        onFailure: @escaping @MainActor (Reason) -> Void,
        content: @escaping @MainActor (OwnIDUIContainerController) -> Content
    ) {
        guard activePresentation == nil else {
            onFailure(.systemError(details: "Launch already in progress"))
            return
        }

        let containerController = OwnIDUIContainerController { [weak self] in
            self?.dismissActivePresentation()
        }

        let presentation = ActivePresentation(
            presenter: self,
            content: AnyView(content(containerController)),
            themeStore: themeStore,
            containerController: containerController,
            onFailure: onFailure
        )
        activePresentation = presentation

        presentation.viewController.onDidOpen = { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            guard presentation === self.activePresentation else {
                if presentation.hasStartedPresentation {
                    presentation.viewController.requestDismiss(completion: {})
                }
                return
            }
            guard !presentation.hasOpened else { return }

            presentation.hasOpened = true
            presentation.presentWatchdog?.cancel()
            presentation.presentWatchdog = nil
        }
        presentation.viewController.onDidDisappearUnexpectedly = { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            guard presentation === self.activePresentation else { return }
            self.logger?.logW(source: self, prefix: "presentOnHost", message: "Bottom sheet disappeared unexpectedly")

            presentation.cancelTransientTasks()
            self.activePresentation = nil
        }

        containerController.addClosedHandler { [weak self, weak presentation] _ in
            guard let self, let presentation else { return }
            guard presentation === self.activePresentation else { return }
            presentation.cancelTransientTasks()
            self.activePresentation = nil
        }

        presentation.presentLoopTask = Task { @MainActor [weak self, weak presentation] in
            guard let self else { return }
            guard let presentation else { return }
            await self.runPresentLoop(retries: TimingConstants.maxRetries, presentation: presentation)
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
    private func runPresentLoop(retries: Int, presentation: ActivePresentation) async {
        defer { presentation.presentLoopTask = nil }

        for retry in 0...retries {
            if Task.isCancelled { return }
            guard presentation === activePresentation else { return }

            guard let host = uiContextProvider.topMostViewController(nil) else {
                if retry < retries {
                    try? await Task.sleep(nanoseconds: TimingConstants.retryDelayNs)
                    continue
                }
                failPresentation(
                    presentation: presentation,
                    logMessage: "Top view controller not found",
                    reason: .systemError(details: "Top view controller not found")
                )
                return
            }

            if host.isBeingDismissed || host.view.window == nil || host.presentedViewController?.isBeingDismissed == true {
                if retry < retries {
                    try? await Task.sleep(nanoseconds: TimingConstants.retryDelayNs)
                    continue
                }
                failPresentation(
                    presentation: presentation,
                    logMessage: "Host is dismissing or off-screen",
                    reason: .systemError(details: "Host is dismissing or off-screen")
                )
                return
            }

            presentOnHost(host: host, presentation: presentation)
            return
        }
    }

    @MainActor
    private func presentOnHost(host: UIViewController, presentation: ActivePresentation) {
        guard presentation === activePresentation else { return }

        logger?.logD(source: self, prefix: "presentOnHost", message: "Presenting bottom sheet")
        presentation.hasStartedPresentation = true

        presentation.presentWatchdog?.cancel()
        presentation.presentWatchdog = Task { @MainActor [weak self, weak presentation] in
            try? await Task.sleep(nanoseconds: TimingConstants.watchdogDelayNs)
            guard let self else { return }
            guard let presentation else { return }
            guard presentation === self.activePresentation else { return }
            guard !presentation.hasOpened else { return }
            self.failPresentation(
                presentation: presentation,
                logMessage: "Presentation completion timed out",
                reason: .systemError(details: "Presentation completion timed out")
            )
        }

        if #unavailable(iOS 15.0) {
            host.view.window?.endEditing(true)
        }

        host.present(presentation.viewController, animated: false)
    }

    @MainActor
    private func failPresentation(presentation: ActivePresentation, logMessage: String, reason: Reason) {
        guard presentation === activePresentation else { return }
        presentation.cancelTransientTasks()
        activePresentation = nil
        if presentation.hasStartedPresentation {
            presentation.viewController.requestDismiss { [weak presentation] in
                presentation?.containerController.markClosed()
            }
        } else {
            presentation.containerController.markClosed()
        }
        logger?.logW(source: self, prefix: "BottomSheetPresenter", message: logMessage)
        presentation.onFailure(reason)
    }
}
