import WebKit

/// Resolves UI only from the exact `WKWebView` attached to one bridge.
///
/// After a successful attach, detach closes this context; if the web view is gone or is not connected to a window,
/// resolution fails instead of selecting another application window.
@MainActor
internal final class WebBridgeUIContextProviderImpl: UIContextProvider {
    private enum State {
        case unbound
        case bound
        case closed
    }

    private var state: State = .unbound
    private weak var webView: WKWebView?

    nonisolated init() {}

    internal func bind(webView: WKWebView) throws {
        switch state {
        case .unbound:
            self.webView = webView
            state = .bound
        case .bound:
            throw UIContextResolutionError(reason: .unavailable, message: "The WebBridge UI context is already bound.")
        case .closed:
            throw UIContextResolutionError(reason: .ownerClosed, message: "The WebBridge UI context owner has closed.")
        }
    }

    internal func resetAfterFailedAttach() {
        guard case .bound = state else { return }
        webView = nil
        state = .unbound
    }

    internal func close() {
        webView = nil
        state = .closed
    }

    internal func current() -> UIContextResult {
        switch state {
        case .unbound:
            return .failure(UIContextResolutionError(reason: .unavailable, message: "WebBridge is not attached to a WebView."))
        case .closed:
            return .failure(UIContextResolutionError(reason: .ownerClosed, message: "The WebBridge UI context owner has closed."))
        case .bound:
            break
        }

        guard let webView else {
            state = .closed
            return .failure(UIContextResolutionError(reason: .ownerClosed, message: "The WebBridge WebView owner has closed."))
        }
        guard let window = webView.window else {
            return .failure(UIContextResolutionError(reason: .unavailable, message: "The WebBridge WebView is not attached to a window."))
        }

        return UIContextWindowResolver.resolve(window: window)
    }
}
