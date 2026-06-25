import Foundation

/// WebBridge UI adapter that delegates presentation to the Core SDK UIKit presenter.
///
/// The adapter exposes a no-throw UI startup boundary to the operation. Immediate presentation failures are returned to
/// the operation state machine; delayed presentation failures are delivered through `onStartError`.
internal final class WebBridgeUIImpl: WebBridgeUI {
    private let presenter: any WebBridgePresenter

    init(presenter: any WebBridgePresenter) {
        self.presenter = presenter
    }

    @MainActor
    func start(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration = .default,
        onDetach: @MainActor @escaping () -> Void,
        onStartError: @MainActor @escaping (WebBridgeOperationFailure.UI) -> Void
    ) -> WebBridgeOperationFailure.UI? {
        presenter.present(
            controller: controller,
            webViewConfiguration: webViewConfiguration,
            onWebViewDetach: onDetach,
            onFailure: onStartError
        )
    }
}
