import SwiftUI
import WebKit

/// UIKit host for the SDK-managed WebBridge screen.
///
/// The controller embeds ``WebBridgeScreen`` in a full-screen `UIHostingController`, keeps UIKit background colors
/// aligned with the active ``WebBridgeUIState``, and pins SDK-managed WebBridge UI to portrait orientation.
///
/// For hosting configurations that deliver a dismiss attempt through UIKit presentation callbacks, the controller
/// aligns that request with the active WebBridge session: if the embedded `WKWebView` has back-stack history, the
/// request navigates back in the page flow; otherwise the active ``WebBridgeUIState/onWebViewCancel`` callback is
/// invoked so the operation can finish with ``OperationResult/canceled(_:)``. A direct abort is used only when no
/// active UI state is available.
internal final class WebBridgeViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let screen: WebBridgeScreen
    private let abortOperation: @MainActor (Reason) -> Void
    private let logger: OwnIDLogRouter?
    private lazy var hostingController = UIHostingController(rootView: screen)

    internal var activeUIState: WebBridgeUIState? {
        didSet {
            let color = activeUIState.map { $0.backgroundColor ?? WebBridgeUIDefaults.backgroundColor } ?? .clear
            view.backgroundColor = color
            hostingController.view.backgroundColor = color
        }
    }
    internal var onDidAppear: (@MainActor () -> Void)?

    init(
        screen: WebBridgeScreen,
        logger: OwnIDLogRouter? = nil,
        abortOperation: @escaping @MainActor (Reason) -> Void
    ) {
        self.screen = screen
        self.abortOperation = abortOperation
        self.logger = logger
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        isModalInPresentation = true
        presentationController?.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presentationController?.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        if let webView = findWKWebView(in: hostingController.view), webView.canGoBack {
            logger?.logD(source: self, prefix: "DismissAttempt", message: "webView.canGoBack -> goBack()")
            webView.goBack()
        } else {
            let reason = Reason.userClose(details: "User navigated back")
            if let activeUIState {
                logger?.logD(source: self, prefix: "DismissAttempt", message: "No back stack -> onWebViewCancel(UserClose)")
                activeUIState.onWebViewCancel(reason)
            } else {
                logger?.logD(source: self, prefix: "DismissAttempt", message: "No active UI state -> abort(UserClose)")
                abortOperation(reason)
            }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Intentionally left empty; presenter coordinates dismissal after operation completion.
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    private func findWKWebView(in view: UIView) -> WKWebView? {
        if let wv = view as? WKWebView { return wv }
        for sub in view.subviews {
            if let wv = findWKWebView(in: sub) { return wv }
        }
        return nil
    }
}
