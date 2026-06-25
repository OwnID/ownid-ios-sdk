import SwiftUI
import UIKit

/// Presents and dismisses the SDK-managed WebBridge screen.
///
/// The presenter owns the UIKit presentation boundary for WebBridge operations. It allows one active SDK-managed
/// WebBridge launch at a time, retries while the host view controller is transitioning, and uses a watchdog to settle a
/// presentation attempt whose UIKit completion never arrives.
///
/// Immediate startup failures are returned. Delayed presentation failures are reported through `onFailure`, with detach
/// callbacks suppressed for failures that happen before a WebView is successfully presented. Normal user completion,
/// cancellation, and terminal WebView errors flow through the operation result instead.
internal protocol WebBridgePresenter: Sendable {
    @MainActor
    @discardableResult
    func present(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration,
        onWebViewDetach: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (WebBridgeOperationFailure.UI) -> Void
    ) -> WebBridgeOperationFailure.UI?
    @MainActor func dismiss()
}

internal final class WebBridgePresenterImpl: WebBridgePresenter, @unchecked Sendable {
    private enum TimingConstants {
        static let maxRetries = 3
        static let retryDelayNs: UInt64 = 160_000_000
        static let watchdogDelayNs: UInt64 = 8_000_000_000
        static let dismissalVerificationDelayNs: UInt64 = 1_000_000_000
    }

    @MainActor
    private final class DetachGate {
        private var isSuppressed = false

        func suppress() {
            isSuppressed = true
        }

        func handleDetach(_ onWebViewDetach: @MainActor () -> Void) {
            guard !isSuppressed else { return }
            onWebViewDetach()
        }
    }

    @MainActor
    private final class PresentationSession {
        /// Session state keeps launch release, dismissal, and async task cancellation idempotent across presenter
        /// dismissal, operation settlement, and presenter deallocation.
        enum DeinitCleanup {
            case release
            case dismiss
            case dismissIfAttached
            case releaseWhenDetached
        }

        enum Phase {
            case waitingToPresent
            case presenting(pendingDismiss: Bool)
            case presented
            case finishing

            var hasStartedPresentation: Bool {
                switch self {
                case .waitingToPresent:
                    return false
                case .presenting, .presented, .finishing:
                    return true
                }
            }

            var isFinishing: Bool {
                guard case .finishing = self else { return false }
                return true
            }
        }

        let launchID: UInt
        let viewController: WebBridgeViewController
        let detachGate: DetachGate
        var watchdog: Task<Void, Never>?
        var settlementObserver: Task<Void, Never>?
        var phase: Phase = .waitingToPresent

        init(launchID: UInt, viewController: WebBridgeViewController, detachGate: DetachGate) {
            self.launchID = launchID
            self.viewController = viewController
            self.detachGate = detachGate
        }

        deinit {
            watchdog?.cancel()
            settlementObserver?.cancel()

            let launchID = launchID
            let viewController = viewController
            let cleanup: DeinitCleanup
            switch phase {
            case .waitingToPresent:
                cleanup = .release
            case .presenting:
                cleanup = .dismissIfAttached
            case .presented:
                cleanup = .dismiss
            case .finishing:
                cleanup = .releaseWhenDetached
            }
            Task { @MainActor in
                WebBridgePresenterImpl.cleanupDeinitializedSession(
                    launchID: launchID,
                    viewController: viewController,
                    cleanup: cleanup
                )
            }
        }

        func cancelTasks() {
            watchdog?.cancel()
            watchdog = nil
            settlementObserver?.cancel()
            settlementObserver = nil
        }
    }

    private let uiContextProvider: any UIContextProvider
    private let logger: OwnIDLogRouter?

    @MainActor private var activeSession: PresentationSession?
    @MainActor private static var isLaunchInProgress: Bool = false
    @MainActor private static var activeLaunchID: UInt?
    @MainActor private static var nextLaunchID: UInt = 0

    public init(uiContextProvider: any UIContextProvider, logger: OwnIDLogRouter?) {
        self.uiContextProvider = uiContextProvider
        self.logger = logger
    }

    @MainActor
    @discardableResult
    public func present(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration = .default,
        onWebViewDetach: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (WebBridgeOperationFailure.UI) -> Void
    ) -> WebBridgeOperationFailure.UI? {
        logger?.logD(source: self, prefix: #function, message: "Invoked")
        if activeSession != nil {
            logger?.logD(source: self, prefix: #function, message: "Launch suppressed: already in progress")
            return .init(errorCode: .unknown, message: "Failed to present WebBridge UI: Launch already in progress")
        }

        guard let launchID = acquireLaunchID() else {
            logger?.logD(source: self, prefix: #function, message: "Launch suppressed: already in progress")
            return .init(errorCode: .unknown, message: "Failed to present WebBridge UI: Launch already in progress")
        }

        weak var presentedWebBridgeController: WebBridgeViewController?
        let detachGate = DetachGate()
        let screen = WebBridgeScreen(
            controller: controller,
            webViewConfiguration: webViewConfiguration,
            logger: logger,
            onWebViewDetach: { detachGate.handleDetach(onWebViewDetach) },
            onActiveUIStateChanged: { uiState in presentedWebBridgeController?.activeUIState = uiState }
        )
        let webBridgeViewController = WebBridgeViewController(
            screen: screen,
            logger: logger,
            abortOperation: { reason in controller.abort(reason: reason) }
        )
        presentedWebBridgeController = webBridgeViewController
        webBridgeViewController.modalPresentationStyle = .fullScreen

        let session = PresentationSession(launchID: launchID, viewController: webBridgeViewController, detachGate: detachGate)
        webBridgeViewController.onDidAppear = { [weak self, weak session] in
            guard let self, let session, self.isSessionActive(session) else { return }
            self.markPresented(session, message: "onDidAppear")
        }
        activeSession = session

        session.settlementObserver = Task { [weak self, weak session, controller] in
            let stateStream = await MainActor.run { controller.stateStream() }
            for await state in stateStream {
                guard case .completed = state else { continue }
                await MainActor.run {
                    guard let self, let session, self.isSessionActive(session) else { return }
                    self.dismiss()
                }
                break
            }
        }

        presentScreen(session: session, retry: TimingConstants.maxRetries, onFailure: onFailure)
        return nil
    }

    @MainActor
    public func dismiss() {
        logger?.logD(source: self, prefix: #function, message: "Invoked")
        guard let session = activeSession else { return }
        requestDismiss(session: session)
    }

    @MainActor
    private func presentScreen(
        session: PresentationSession,
        retry: Int,
        onFailure: @escaping @MainActor (WebBridgeOperationFailure.UI) -> Void
    ) {
        logger?.logD(source: self, prefix: #function, message: "Invoked")
        guard isSessionActive(session) else { return }

        guard let hostViewController = uiContextProvider.topMostViewController(nil) else {
            if retry > 0 {
                schedulePresentRetry(session: session, retry: retry, onFailure: onFailure)
            } else {
                fail(session: session, message: "Top view controller not found", onFailure: onFailure)
            }
            return
        }

        if let transitionCoordinator = hostViewController.transitionCoordinator {
            guard retry > 0 else {
                fail(session: session, message: "Host is dismissing or off-screen", onFailure: onFailure)
                return
            }
            let didSchedule = transitionCoordinator.animate(alongsideTransition: nil) { [weak self, weak session] _ in
                Task { @MainActor in
                    guard let self, let session else { return }
                    self.presentScreen(session: session, retry: retry - 1, onFailure: onFailure)
                }
            }
            if !didSchedule {
                schedulePresentRetry(session: session, retry: retry, onFailure: onFailure)
            }
            return
        }

        if hostViewController.isBeingDismissed || hostViewController.view.window == nil
            || hostViewController.isBeingPresented
            || hostViewController.presentedViewController?.isBeingDismissed == true
        {
            if retry > 0 {
                schedulePresentRetry(session: session, retry: retry, onFailure: onFailure)
            } else {
                fail(session: session, message: "Host is dismissing or off-screen", onFailure: onFailure)
            }
            return
        }

        session.phase = .presenting(pendingDismiss: false)

        session.watchdog?.cancel()
        session.watchdog = Task { @MainActor [weak self, weak session] in
            do {
                try await Task.sleep(nanoseconds: TimingConstants.watchdogDelayNs)
            } catch {
                return
            }
            guard let self, let session, self.isSessionActive(session) else { return }

            if session.viewController.viewIfLoaded?.window != nil {
                self.markPresented(session, message: "watchdog attached")
                return
            }

            self.fail(session: session, message: "Presentation completion timed out", onFailure: onFailure)
        }

        hostViewController.present(session.viewController, animated: true) { [weak self, weak session] in
            guard let self, let session, self.isSessionActive(session) else { return }
            self.markPresented(session, message: "completion")
        }
    }

    @MainActor
    private func acquireLaunchID() -> UInt? {
        guard Self.isLaunchInProgress == false else { return nil }
        Self.nextLaunchID &+= 1
        let launchID = Self.nextLaunchID
        Self.activeLaunchID = launchID
        Self.isLaunchInProgress = true
        return launchID
    }

    @MainActor
    private func isSessionActive(_ session: PresentationSession) -> Bool {
        activeSession === session && Self.isLaunchInProgress && Self.activeLaunchID == session.launchID
    }

    @MainActor
    private static func releaseLaunchLockIfOwned(_ launchID: UInt) {
        guard Self.activeLaunchID == launchID else { return }
        Self.isLaunchInProgress = false
        Self.activeLaunchID = nil
    }

    @MainActor
    private static func cleanupDeinitializedSession(
        launchID: UInt,
        viewController: WebBridgeViewController,
        cleanup: PresentationSession.DeinitCleanup
    ) {
        switch cleanup {
        case .release:
            releaseLaunchLockIfOwned(launchID)
        case .dismiss:
            dismissDeinitializedSession(launchID: launchID, viewController: viewController)
        case .dismissIfAttached:
            guard viewController.view.window != nil || viewController.presentingViewController != nil else {
                releaseLaunchLockIfOwned(launchID)
                return
            }
            dismissDeinitializedSession(launchID: launchID, viewController: viewController)
        case .releaseWhenDetached:
            releaseDeinitializedSessionWhenDetached(launchID: launchID, viewController: viewController)
        }
    }

    @MainActor
    private static func dismissDeinitializedSession(launchID: UInt, viewController: WebBridgeViewController) {
        viewController.dismiss(animated: true) {
            Task { @MainActor in releaseLaunchLockIfOwned(launchID) }
        }
        releaseDeinitializedSessionWhenDetached(launchID: launchID, viewController: viewController)
    }

    @MainActor
    private static func releaseDeinitializedSessionWhenDetached(launchID: UInt, viewController: WebBridgeViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(TimingConstants.dismissalVerificationDelayNs))) {
            Task { @MainActor in
                guard viewController.view.window == nil else { return }
                releaseLaunchLockIfOwned(launchID)
            }
        }
    }

    @MainActor
    private func fail(session: PresentationSession, message: String, onFailure: @escaping @MainActor (WebBridgeOperationFailure.UI) -> Void) {
        guard isSessionActive(session) else { return }
        logger?.logW(source: self, prefix: "WebBridgePresenter", message: message)
        let error = WebBridgeOperationFailure.UI(errorCode: .unknown, message: "Failed to present WebBridge UI: \(message)")
        let hasStartedPresentation = session.phase.hasStartedPresentation
        session.detachGate.suppress()

        guard hasStartedPresentation else {
            finish(session: session, dismiss: false) {
                onFailure(error)
            }
            return
        }

        onFailure(error)
        finish(session: session, dismiss: true, completion: {})
    }

    @MainActor
    private func schedulePresentRetry(
        session: PresentationSession,
        retry: Int,
        onFailure: @escaping @MainActor (WebBridgeOperationFailure.UI) -> Void
    ) {
        let launchID = session.launchID
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(TimingConstants.retryDelayNs))) {
            [weak self, weak session] in
            guard let self else {
                Task { @MainActor in Self.releaseLaunchLockIfOwned(launchID) }
                return
            }
            guard let session else { return }
            self.presentScreen(session: session, retry: retry - 1, onFailure: onFailure)
        }
    }

    @MainActor
    private func markPresented(_ session: PresentationSession, message: String) {
        guard isSessionActive(session), !session.phase.isFinishing else { return }
        session.watchdog?.cancel()
        session.watchdog = nil
        logger?.logD(source: self as Any, prefix: #function, message: message)

        let shouldDismiss: Bool
        switch session.phase {
        case .presenting(let pendingDismiss):
            shouldDismiss = pendingDismiss
        case .presented:
            shouldDismiss = false
        case .waitingToPresent, .finishing:
            return
        }

        session.phase = .presented
        if shouldDismiss {
            finish(session: session, dismiss: true, completion: {})
        }
    }

    @MainActor
    private func requestDismiss(session: PresentationSession) {
        guard isSessionActive(session), !session.phase.isFinishing else { return }

        switch session.phase {
        case .waitingToPresent:
            finish(session: session, dismiss: false, completion: {})
        case .presenting:
            session.phase = .presenting(pendingDismiss: true)
        case .presented:
            finish(session: session, dismiss: true, completion: {})
        case .finishing:
            return
        }
    }

    @MainActor
    private func finish(session: PresentationSession, dismiss: Bool, completion: @escaping @MainActor () -> Void) {
        guard isSessionActive(session), !session.phase.isFinishing else { return }
        session.phase = .finishing
        session.cancelTasks()
        let launchID = session.launchID

        let finishState: @MainActor () -> Void = { [weak self, session] in
            guard Self.activeLaunchID == launchID else { return }
            if let self, self.activeSession === session {
                self.activeSession = nil
            }
            Self.releaseLaunchLockIfOwned(launchID)
            completion()
        }

        guard dismiss else {
            finishState()
            return
        }

        session.viewController.dismiss(animated: true) {
            Task { @MainActor in finishState() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(TimingConstants.dismissalVerificationDelayNs))) {
            Task { @MainActor [weak self, weak session] in
                guard let self, let session, self.isSessionActive(session), session.phase.isFinishing else { return }
                guard session.viewController.view.window == nil else { return }
                finishState()
            }
        }
    }
}

#if DEBUG
    extension WebBridgePresenterImpl {
        @MainActor
        internal static func __testResetLaunchFlag() {
            Self.isLaunchInProgress = false
            Self.activeLaunchID = nil
        }
    }
#endif
