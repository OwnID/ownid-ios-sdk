import SwiftUI

/// SwiftUI screen that renders the active WebBridge session.
///
/// This view observes ``WebBridgeOperationController/stateStream()`` for rendered content in the SDK-managed
/// presentation path. It keeps the rendered WebView in sync with the latest operation state, exposes the active
/// ``WebBridgeUIState`` to the hosting view controller, and cancels its observation task when the SwiftUI screen
/// disappears.
internal struct WebBridgeScreen: View {
    let controller: any WebBridgeOperationController
    let webViewConfiguration: WebBridgeWebViewConfiguration
    let logger: OwnIDLogRouter?

    let onWebViewDetach: @MainActor () -> Void
    private let onActiveUIStateChanged: @MainActor (WebBridgeUIState?) -> Void

    @State private var operationState: WebBridgeOperationState = .created
    @State private var observationTask: Task<Void, Never>?

    internal init(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration = .default,
        logger: OwnIDLogRouter?,
        onWebViewDetach: @escaping @MainActor () -> Void,
        onActiveUIStateChanged: @escaping @MainActor (WebBridgeUIState?) -> Void
    ) {
        self.controller = controller
        self.webViewConfiguration = webViewConfiguration
        self.logger = logger
        self.onWebViewDetach = onWebViewDetach
        self.onActiveUIStateChanged = onActiveUIStateChanged
    }

    public var body: some View {
        WebBridgeWebView(
            state: operationState,
            webViewConfiguration: webViewConfiguration,
            logger: logger,
            onDetach: onWebViewDetach
        )
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
    }

    @MainActor
    private func observeState() async {
        for await state in controller.stateStream() {
            operationState = state
            switch state {
            case .active(let uiState):
                onActiveUIStateChanged(uiState)
            case .created:
                onActiveUIStateChanged(nil)
            case .completed:
                onActiveUIStateChanged(nil)
                return
            }
        }
    }

    @MainActor
    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { await observeState() }
    }

    @MainActor
    private func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        onActiveUIStateChanged(nil)
    }
}
