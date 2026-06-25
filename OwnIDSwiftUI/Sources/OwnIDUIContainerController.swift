import OwnIDCore
import SwiftUI
import UIKit

/// Coordinates one app-owned presentation container for ``OwnIDOperationView``.
///
/// Use this controller when you present OwnID operation UI inside your own SwiftUI sheet, full-screen cover, dialog,
/// or overlay.
///
/// Create a new controller for each time your app presents OwnID UI in its own sheet, full-screen cover, dialog, or
/// overlay. Keep the same controller for that whole presentation cycle, pass it to ``OwnIDOperationView``, and attach
/// ``View/ownIDOperationContainer(_:)`` to the root of the presented content so the SDK can track when the container
/// opens and closes. Removing ``OwnIDOperationView`` from the view hierarchy is not a container-close signal; attach
/// the modifier or call ``markClosed()`` from the container lifecycle when that container is fully dismissed.
///
/// ``close()`` invokes your close action, but the container is not considered closed until ``markClosed()`` runs. If
/// the container closes before the operation settles, the operation is canceled as a user close. If the operation
/// settles first, the SDK invokes your close action and the later ``markClosed()`` call only completes presentation
/// cleanup.
///
/// A controller is single-use. Do not reuse a closed controller or replace the controller passed to
/// ``OwnIDOperationView`` while the current sheet, full-screen cover, dialog, or overlay is still open. Create a new
/// controller for the next presentation. All public lifecycle methods are main-actor isolated.
@MainActor
public final class OwnIDUIContainerController: ObservableObject {
    /// An app-owned action that starts dismissing the presentation container.
    ///
    /// The SDK invokes this action when the operation UI should close. The action should start dismissal, for example
    /// by setting a sheet binding to `false` or hiding a custom overlay. Your app must still report final teardown
    /// through ``markClosed()``.
    public typealias CloseAction = @MainActor () -> Void

    private enum CloseRequest {
        case dismissWithoutAbort
        case abortOnClose(Reason)
    }

    private enum State {
        case idle
        case opened
        case closing(request: CloseRequest, wasOpened: Bool)
        case closed(request: CloseRequest?)
    }

    @Published private var state: State = .idle

    private let closeAction: CloseAction
    private var onClosedHandlers: [@MainActor (Reason?) -> Void] = []

    /// Creates a controller for one app-owned presentation cycle.
    ///
    /// - Parameter closeAction: App-owned dismissal action. The SDK invokes it at most once when the operation UI
    ///   should close. The action starts dismissal; it does not replace ``markClosed()``.
    public init(closeAction: @escaping CloseAction) {
        self.closeAction = closeAction
    }

    internal convenience init() {
        self.init(closeAction: {})
    }

    /// Marks the presentation container as fully visible and ready for input.
    ///
    /// ``View/ownIDOperationContainer(_:)`` calls this automatically for SwiftUI containers. Call it yourself only for
    /// non-SwiftUI containers after their presentation animation has completed. Repeated calls during the same cycle
    /// are ignored.
    public func markOpened() {
        guard case .idle = state else { return }
        state = .opened
    }

    /// Requests app-managed dismissal for this container.
    ///
    /// This starts the close action supplied to ``init(closeAction:)``. It does not immediately abort the active
    /// operation. Cancellation, if needed, is decided when the container reaches ``markClosed()``. Repeated calls during
    /// the same cycle are ignored. This method starts dismissal; it does not replace ``markClosed()``.
    public func close() {
        requestClose(.abortOnClose(.userClose(details: "Operation container closed")))
    }

    /// Marks the presentation container as fully closed.
    ///
    /// ``View/ownIDOperationContainer(_:)`` calls this automatically for SwiftUI containers. Call it yourself only for
    /// non-SwiftUI containers.
    ///
    /// This is the terminal presentation lifecycle event. If the operation has not settled yet, the SDK treats the
    /// close as a user close. If the operation has already settled, this only finalizes presentation cleanup. Repeated
    /// calls are ignored. After this call, discard the controller.
    public func markClosed() {
        guard !isClosed else { return }
        let request = currentCloseRequest
        let abortReason = abortReason(for: request)
        state = .closed(request: request)
        let handlers = onClosedHandlers
        onClosedHandlers.removeAll()
        handlers.forEach { $0(abortReason) }
    }

    internal var isOpened: Bool {
        switch state {
        case .opened:
            return true
        case .closing(_, let wasOpened):
            return wasOpened
        case .idle, .closed:
            return false
        }
    }

    internal var isClosed: Bool {
        if case .closed = state { return true }
        return false
    }

    internal var isClosing: Bool {
        switch state {
        case .closing, .closed:
            return true
        case .idle, .opened:
            return false
        }
    }

    internal func requestDismissWithoutAbort() {
        requestClose(.dismissWithoutAbort)
    }

    internal func addClosedHandler(_ handler: @escaping @MainActor (Reason?) -> Void) {
        guard !isClosed else {
            handler(abortReason(for: currentCloseRequest))
            return
        }

        onClosedHandlers.append(handler)
    }

    private var currentCloseRequest: CloseRequest? {
        switch state {
        case .closing(let request, _):
            return request
        case .closed(let request):
            return request
        case .idle, .opened:
            return nil
        }
    }

    private func requestClose(_ request: CloseRequest) {
        switch state {
        case .idle:
            state = .closing(request: request, wasOpened: false)
        case .opened:
            state = .closing(request: request, wasOpened: true)
        case .closing, .closed:
            return
        }

        closeAction()
    }

    private func abortReason(for request: CloseRequest?) -> Reason? {
        switch request {
        case .dismissWithoutAbort:
            return nil
        case .abortOnClose(let reason):
            return reason
        case nil:
            return .userClose(details: "Operation container closed")
        }
    }
}

extension View {
    /// Connects an app-owned presentation container to ``OwnIDOperationView`` lifecycle tracking.
    ///
    /// Use this when you pass an ``OwnIDUIContainerController`` to ``OwnIDOperationView`` and present that view inside
    /// your own sheet, full-screen cover, dialog, or overlay. Attach the modifier to the root of the presented
    /// content. The SDK then tracks when the container appears and disappears, and suppresses text input focus while
    /// dismissal is in progress. Built-in operation content uses the open signal to delay one-time initial focus until
    /// the surrounding presentation is ready.
    ///
    /// Do not attach the same controller to multiple simultaneously visible containers.
    ///
    /// - Parameter controller: The same controller passed to ``OwnIDOperationView`` for the current presentation cycle.
    public func ownIDOperationContainer(_ controller: OwnIDUIContainerController) -> some View {
        modifier(OperationContainerModifier(controller: controller))
    }
}

private struct OperationContainerModifier: ViewModifier {
    @ObservedObject private var controller: OwnIDUIContainerController

    fileprivate init(controller: OwnIDUIContainerController) {
        _controller = ObservedObject(wrappedValue: controller)
    }

    fileprivate func body(content: Content) -> some View {
        content
            .environment(\.ownIDSuppressTextInputFocus, controller.isClosing)
            .background(
                OperationContainerLifecycleObserver(
                    onDidAppear: { controller.markOpened() },
                    onDidDisappear: { controller.markClosed() }
                )
            )
    }
}

private struct OperationContainerLifecycleObserver: UIViewControllerRepresentable {
    typealias UIViewControllerType = LifecycleViewController
    typealias Coordinator = Void

    private let onDidAppear: @MainActor () -> Void
    private let onDidDisappear: @MainActor () -> Void

    fileprivate init(
        onDidAppear: @escaping @MainActor () -> Void,
        onDidDisappear: @escaping @MainActor () -> Void
    ) {
        self.onDidAppear = onDidAppear
        self.onDidDisappear = onDidDisappear
    }

    @MainActor
    func makeUIViewController(
        context: UIViewControllerRepresentableContext<OperationContainerLifecycleObserver>
    ) -> LifecycleViewController {
        LifecycleViewController(onDidAppear: onDidAppear, onDidDisappear: onDidDisappear)
    }

    @MainActor
    func updateUIViewController(
        _ uiViewController: LifecycleViewController,
        context: UIViewControllerRepresentableContext<OperationContainerLifecycleObserver>
    ) {
        uiViewController.onDidAppear = onDidAppear
        uiViewController.onDidDisappear = onDidDisappear
    }
}

@MainActor
private final class LifecycleViewController: UIViewController {
    fileprivate var onDidAppear: @MainActor () -> Void
    fileprivate var onDidDisappear: @MainActor () -> Void

    fileprivate init(
        onDidAppear: @escaping @MainActor () -> Void,
        onDidDisappear: @escaping @MainActor () -> Void
    ) {
        self.onDidAppear = onDidAppear
        self.onDidDisappear = onDidDisappear
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    fileprivate required init?(coder: NSCoder) {
        return nil
    }

    fileprivate override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        self.view = view
    }

    fileprivate override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear()
    }

    fileprivate override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDidDisappear()
    }
}
