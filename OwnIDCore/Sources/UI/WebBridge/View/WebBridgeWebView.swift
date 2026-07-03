import Foundation
import SwiftUI
import UIKit
import WebKit

/// SwiftUI wrapper around the SDK-managed `WKWebView` used by WebBridge operations.
///
/// The wrapper creates the operation WebView with the default website data store, applies optional app-bound-domain
/// navigation limits when available, installs navigation/UI delegates, and applies operation-provided content options.
/// It injects the bridge before the first HTML load when possible and retries after a completed navigation if the first
/// injection path did not run. Dismantling detaches the bridge from the owning operation.
///
/// The coordinator keeps only the initial same-origin document load inside the WebView. Later HTTP(S) navigations and
/// target-frame launches are opened externally, while local/script schemes are blocked and OwnID JavaScript
/// load/exception URLs are converted into terminal WebView errors.
internal struct WebBridgeWebView: UIViewRepresentable {
    private let state: WebBridgeOperationState
    private let webViewConfiguration: WebBridgeWebViewConfiguration
    private let logger: OwnIDLogRouter?
    private let onWebViewDetach: @MainActor @Sendable () -> Void

    init(
        state: WebBridgeOperationState,
        webViewConfiguration: WebBridgeWebViewConfiguration = .default,
        logger: OwnIDLogRouter?,
        onDetach: @MainActor @escaping () -> Void
    ) {
        self.state = state
        self.webViewConfiguration = webViewConfiguration
        self.logger = logger
        self.onWebViewDetach = onDetach
    }

    typealias Coordinator = WebBridgeWebViewCoordinator
    func makeCoordinator() -> Coordinator { Coordinator(logger: logger, onWebViewDetach: onWebViewDetach) }

    func makeUIView(context: SwiftUI.UIViewRepresentableContext<WebBridgeWebView>) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if #available(iOS 14.0, *), webViewConfiguration.limitsNavigationsToAppBoundDomains {
            configuration.limitsNavigationsToAppBoundDomains = true
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        configureWebView(uiView: view, for: state, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: SwiftUI.UIViewRepresentableContext<WebBridgeWebView>) {
        if uiView.navigationDelegate !== context.coordinator { uiView.navigationDelegate = context.coordinator }
        if uiView.uiDelegate !== context.coordinator { uiView.uiDelegate = context.coordinator }
        configureWebView(uiView: uiView, for: state, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private func configureWebView(uiView: WKWebView, for state: WebBridgeOperationState, coordinator: Coordinator) {
        switch state {
        case .created:
            coordinator.activeUIState = nil
            uiView.backgroundColor = .clear
            uiView.scrollView.backgroundColor = .clear
            break

        case .active(let uiState):
            coordinator.activeUIState = uiState

            if #available(iOS 16.4, *), let webViewIsInspectable = uiState.webViewIsInspectable {
                uiView.isInspectable = webViewIsInspectable
            }
            uiView.customUserAgent = uiState.userAgent
            let backgroundColor = uiState.backgroundColor ?? WebBridgeUIDefaults.backgroundColor
            uiView.backgroundColor = backgroundColor
            uiView.scrollView.backgroundColor = backgroundColor

            if !coordinator.isBridgeInjected {
                do {
                    try uiState.doWebViewBridgeInject(uiView)
                    coordinator.isBridgeInjected = true
                } catch {
                    uiState.onWebViewTerminalError(error, nil)
                }
            }

            if !coordinator.hasLoaded {
                guard let baseURL = URL(string: uiState.baseUrl) else {
                    uiState.onWebViewTerminalError(nil, "Invalid baseUrl: \(uiState.baseUrl)")
                    return
                }
                coordinator.hasLoaded = true
                coordinator.initialDocumentBaseURL = baseURL
                uiView.loadHTMLString(uiState.html, baseURL: baseURL)
            }

        case .completed:
            coordinator.activeUIState = nil
            break
        }
    }
}

internal final class WebBridgeWebViewCoordinator: NSObject, WKNavigationDelegate {
    internal var activeUIState: WebBridgeUIState?
    internal var isBridgeInjected = false
    internal var hasLoaded = false
    internal var initialDocumentBaseURL: URL?

    private let logger: OwnIDLogRouter?
    private let onWebViewDetach: @MainActor @Sendable () -> Void
    private let openURL: @MainActor @Sendable (URL) -> Void

    static var isAppExtension: Bool {
        if Bundle.main.bundleURL.pathExtension == "appex" { return true }
        if Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil { return true }
        return false
    }

    @MainActor
    private static func defaultOpenURL(_ url: URL) {
        guard !isAppExtension else { return }
        #if canImport(UIKit)
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #else
            _ = url
        #endif
    }

    init(
        logger: OwnIDLogRouter?,
        onWebViewDetach: @escaping @MainActor @Sendable () -> Void,
        openURL: @escaping @MainActor @Sendable (URL) -> Void = WebBridgeWebViewCoordinator.defaultOpenURL
    ) {
        self.logger = logger
        self.onWebViewDetach = onWebViewDetach
        self.openURL = openURL
    }

    func detach() {
        activeUIState = nil
        isBridgeInjected = false
        hasLoaded = false
        initialDocumentBaseURL = nil
        Task { @MainActor in onWebViewDetach() }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.scheme?.lowercased() == WebBridgeUIDefaults.ownIdScheme {
            handleOwnIdURL(url)
            decisionHandler(.cancel)
            return
        }

        if let scheme = url.scheme?.lowercased(), ["javascript", "data", "file", "content", "intent"].contains(scheme) {
            decisionHandler(.cancel)
            return
        }

        if allowsNavigationInWebView(
            url,
            navigationType: navigationAction.navigationType,
            targetFrameIsNil: navigationAction.targetFrame == nil
        ) {
            decisionHandler(.allow)
        } else {
            Task { @MainActor in openURL(url) }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        initialDocumentBaseURL = nil

        if !isBridgeInjected, let uiState = activeUIState {
            do {
                try uiState.doWebViewBridgeInject(webView)
                isBridgeInjected = true
            } catch {
                Task { @MainActor in uiState.onWebViewTerminalError(error, nil) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        logger?.logW(source: self, prefix: "navigation", message: "WebView navigation failed: \(error.localizedDescription)", cause: error)
        initialDocumentBaseURL = nil
        if let uiState = activeUIState {
            Task { @MainActor in uiState.onWebViewTerminalError(error, nil) }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        logger?.logW(
            source: self,
            prefix: "navigation",
            message: "WebView provisional navigation failed: \(error.localizedDescription)",
            cause: error
        )
        initialDocumentBaseURL = nil
        if let uiState = activeUIState {
            Task { @MainActor in uiState.onWebViewTerminalError(error, nil) }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isBridgeInjected = false
        hasLoaded = false
        logger?.logW(source: self, prefix: "navigation", message: "WebView render process terminated")
        if let uiState = activeUIState {
            Task { @MainActor in uiState.onWebViewTerminalError(nil, "WebView render process terminated") }
        }
    }

    // MARK: WKUIDelegate
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        if url.scheme?.lowercased() == WebBridgeUIDefaults.ownIdScheme {
            handleOwnIdURL(url)
            return nil
        }

        if let scheme = url.scheme?.lowercased(), ["javascript", "data", "file", "content", "intent"].contains(scheme) {
            return nil
        }

        if !allowsNavigationInWebView(url, navigationType: navigationAction.navigationType, targetFrameIsNil: true) {
            Task { @MainActor in openURL(url) }
        }
        return nil
    }

    // MARK: ownid:// handlers
    internal func handleOwnIdURL(_ url: URL) {
        guard let host = url.host?.lowercased() else { return }
        switch host {
        case WebBridgeUIDefaults.jsLoadErrorHost:
            logger?.logW(source: self, prefix: "handleOwnIdURL", message: "JS load error: \(url.absoluteString)")
            if let uiState = activeUIState {
                Task { @MainActor in uiState.onWebViewTerminalError(nil, "JS load error: \(url.absoluteString)") }
            }
        case WebBridgeUIDefaults.jsExceptionHost:
            let message = queryValue(from: url, for: "ex") ?? url.absoluteString
            logger?.logW(source: self, prefix: "handleOwnIdURL", message: "JS exception: \(message)")
            if let uiState = activeUIState {
                Task { @MainActor in uiState.onWebViewTerminalError(nil, message) }
            }
        default:
            break
        }
    }

    internal func queryValue(from url: URL, for name: String) -> String? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = comps.queryItems else { return nil }
        return items.first(where: { $0.name == name })?.value
    }

    internal func allowsNavigationInWebView(
        _ url: URL,
        navigationType: WKNavigationType,
        targetFrameIsNil: Bool
    ) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        if scheme == "about" { return true }

        // WKNavigationDelegate may ask for policy while loadHTMLString boots the
        // flow document. Keep only that initial same-origin document load inside
        // this WebView; later HTTP(S) navigations leave the flow and must open
        // externally.
        guard let initialDocumentBaseURL,
            targetFrameIsNil == false,
            scheme == "http" || scheme == "https",
            navigationType == .other || navigationType == .reload
        else {
            return false
        }

        let defaultPort = scheme == "http" ? 80 : scheme == "https" ? 443 : nil
        return scheme == initialDocumentBaseURL.scheme?.lowercased()
            && url.host?.lowercased() == initialDocumentBaseURL.host?.lowercased()
            && (url.port ?? defaultPort) == (initialDocumentBaseURL.port ?? defaultPort)
    }
}

extension WebBridgeWebViewCoordinator: WKUIDelegate {}

extension WebBridgeWebViewCoordinator {
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        completionHandler()
    }
}
