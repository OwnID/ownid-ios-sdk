import Foundation
import WebKit

/// WKWebView-backed WebBridge implementation.
///
/// A bridge instance is single-use: `attach(webView:allowedOriginRules:)` captures the currently registered plugins,
/// merges explicit origins with the latest server WebView configuration available in this instance, normalizes the
/// effective allowlist, and installs native bridge messaging before page content runs. Registry mutations after
/// attachment do not affect the attached `WKWebView`.
///
/// Detach removes the script message handler, cancels pending message tasks, releases bridge-owned references, and clears
/// the associated lifecycle observer. Previously added `WKUserScript` entries remain owned by the web view's
/// `WKUserContentController`.
///
/// Message handling validates the handler name, payload shape, main-frame source, origin policy, callback path, and
/// plugin key before invoking a plugin. Plugin work is serialized per `WebBridgePluginKey`; tasks canceled by detach
/// stop before evaluating callbacks.
internal final class WebBridgeImpl: NSObject, WKScriptMessageHandler, WebBridge, @unchecked Sendable {
    private enum Constants {
        static let JS_HANDLER_NAME = "__ownidNativeBridgeHandler"

        static func createNativeBridgeJS(namespaces: String) -> String {
            """
            (function () {
                try {
                    // Only inject into the main frame; cross-origin safe guard
                    if (window.top !== window) { return; }
                } catch (e) { return; }

                if (!window.__ownidNativeBridge) {
                    window.__ownidNativeBridge = {
                        getNamespaces: function getNamespaces() { return '\(namespaces)'; },
                        invokeNative: function invokeNative(namespace, action, callbackPath, params, metadata) {
                            try {
                                window.webkit.messageHandlers.\(JS_HANDLER_NAME).postMessage(
                                    { method: 'invokeNative', data: { pluginId: namespace, action, callbackPath, params } }
                                );
                            } catch (error) {
                                setTimeout(function errorHandler() {
                                    eval(callbackPath + '(false);');
                                });
                            }
                        }
                    }
                }
            })();
            """
        }
    }

    private final class AppConfigWebViewCache: @unchecked Sendable {
        private let lock = NSLock()
        private var current: AppConfig.WebViewConfig?

        func store(_ webViewConfig: AppConfig.WebViewConfig?) {
            lock.withLock {
                current = webViewConfig
            }
        }

        func effectiveAllowedOriginRules(for allowedOriginRules: Set<String>) -> Set<String> {
            lock.withLock {
                var effective = allowedOriginRules
                effective.formUnion(current?.allowedOrigins ?? [])
                return effective
            }
        }
    }

    private var associatedObjectKey: UInt8 = 0
    /// Retained on the attached web view so bridge state is shut down if the web view is deallocated before explicit detach.
    private class WebViewLifecycleObserver {
        private let onDeinit: () -> Void
        init(onDeinit: @escaping () -> Void) { self.onDeinit = onDeinit }
        deinit { onDeinit() }
    }

    let plugins: any WebBridgePluginRegistry
    private let coder: any JSONCoder
    private let logger: OwnIDLogRouter?
    private let lock = NSLock()
    private let appConfigCache: AppConfigWebViewCache
    private var appConfigObservationTask: Task<Void, Never>?
    private var isAttached = false
    private var hasInjected = false
    private var attachedPluginsByKey: [WebBridgePluginKey: any WebBridgePlugin] = [:]
    private weak var attachedWebView: WKWebView?
    private weak var attachedUserContentController: WKUserContentController?
    private var originPolicy: OriginPolicy = .any
    private var normalizedOriginRules: Set<String> = []
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private let pluginLockRegistry = PluginLockRegistry()

    nonisolated init(
        plugins: any WebBridgePluginRegistry,
        appConfigProvider: any AppConfigProvider,
        coder: any JSONCoder,
        logger: OwnIDLogRouter?
    ) {
        self.plugins = plugins
        self.coder = coder
        self.logger = logger
        self.appConfigCache = AppConfigWebViewCache()
        super.init()

        let appConfigCache = self.appConfigCache
        self.appConfigObservationTask = Task { [appConfigCache, appConfigProvider] in
            for await config in appConfigProvider.configStream {
                appConfigCache.store(config.webView)
            }
        }
    }

    deinit {
        appConfigObservationTask?.cancel()
    }

    @MainActor
    @discardableResult
    func attach(webView: WKWebView, allowedOriginRules: Set<String> = []) -> WebBridgeError? {
        let effectiveAllowedOriginRules = appConfigCache.effectiveAllowedOriginRules(for: allowedOriginRules)
        let error: WebBridgeError? = lock.withLock {
            do {
                guard !isAttached else { throw WebBridgeError.general("Already attached") }
                guard !hasInjected else { throw WebBridgeError.general("WebBridge instance already used") }

                let registeredPlugins = plugins.snapshot()
                if registeredPlugins.isEmpty {
                    logger?.logW(source: self, prefix: "attach", message: "No plugins available for injection.")
                }

                let normalization = OriginNormalizer.normalizeAllowedOriginRules(effectiveAllowedOriginRules)
                if !normalization.skipped.isEmpty {
                    let skipped = normalization.skipped.map { "'\($0)'" }.joined(separator: ", ")
                    logger?.logW(
                        source: self,
                        prefix: "attach",
                        message: "Skipped \(normalization.skipped.count) invalid allowedOriginRules: \(skipped)"
                    )
                }
                if !normalization.policy.any && normalization.policy.rules.isEmpty {
                    throw WebBridgeError.general("No valid allowedOriginRules provided")
                }
                originPolicy = normalization.policy
                normalizedOriginRules = normalization.normalized

                let pluginNamespaces = registeredPlugins.reduce(into: [String: [String]]()) { acc, plugin in
                    if let (id, actions) = plugin.injectionData() {
                        acc[id] = actions
                    }
                }

                let userContentController = webView.configuration.userContentController
                let namespacesJson = try coder.encodeToString(pluginNamespaces)
                let js = Constants.createNativeBridgeJS(namespaces: namespacesJson)
                userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                logger?.logD(
                    source: self,
                    prefix: "attach",
                    message:
                        "WebBridge injected for origins \(normalizedOriginRules.isEmpty ? ["*"] : normalizedOriginRules) with namespaces: \(pluginNamespaces.keys)"
                )

                userContentController.add(self, name: Constants.JS_HANDLER_NAME)
                attachedPluginsByKey = registeredPlugins.reduce(into: [:]) { result, plugin in
                    result[plugin.key] = plugin
                }
                attachedWebView = webView
                attachedUserContentController = userContentController
                isAttached = true
                hasInjected = true
            } catch {
                attachedPluginsByKey.removeAll()
                attachedWebView = nil
                attachedUserContentController = nil
                logger?.logW(source: self, prefix: "attach", message: "Injection failed", cause: error)
                return WebBridgeError.general("Error attaching bridge", error)
            }
            return nil
        }

        if error == nil {
            let observer = WebViewLifecycleObserver { [weak self] in
                Task { @MainActor in
                    self?.shutdownBridgeState(trigger: "lifecycleObserver.deinit")
                }
            }
            objc_setAssociatedObject(webView, &associatedObjectKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return error
    }

    @MainActor
    func detach() {
        shutdownBridgeState(trigger: #function)
    }

    @MainActor
    private func shutdownBridgeState(trigger: String) {
        var tasksToCancel: [Task<Void, Never>] = []

        lock.withLock {
            guard isAttached else {
                logger?.logI(source: self, prefix: "detach", message: "Bridge already detached")
                return
            }

            let targetWebView = attachedWebView
            let targetUserContentController = attachedUserContentController ?? targetWebView?.configuration.userContentController
            if let targetUserContentController {
                targetUserContentController.removeScriptMessageHandler(forName: Constants.JS_HANDLER_NAME)
            }
            if let targetWebView {
                objc_setAssociatedObject(targetWebView, &associatedObjectKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            if targetUserContentController == nil {
                logger?.logI(source: self, prefix: "detach", message: "\(trigger): no webView available; running state-only cleanup")
            }

            tasksToCancel = Array(pendingTasks.values)
            pendingTasks.removeAll()
            attachedPluginsByKey.removeAll()
            normalizedOriginRules.removeAll()
            originPolicy = .any
            isAttached = false
            attachedWebView = nil
            attachedUserContentController = nil
            logger?.logV(source: self, prefix: "detach", message: "WebBridge successfully detached")
        }

        for task in tasksToCancel {
            task.cancel()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive jsMessage: WKScriptMessage) {
        guard isAttachedToWebView else {
            logger?.logI(source: self, prefix: "userContentController", message: "Message received but bridge is detached. Ignoring.")
            return
        }
        if jsMessage.frameInfo.isMainFrame == false {
            logger?.logI(source: self, prefix: "userContentController", message: "Ignoring message from subframe")
            return
        }
        logger?.logV(source: self, prefix: "userContentController", message: "Received WebBridge message")

        guard jsMessage.body as? [String: Any] != nil
        else {
            logger?.logW(source: self, prefix: "userContentController", message: "Invalid message structure")
            return
        }

        guard jsMessage.name == Constants.JS_HANDLER_NAME else {
            logger?.logW(source: self, prefix: "userContentController", message: "Unsupported handler: \(jsMessage.name)")
            return
        }

        let taskId = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { _ = self.lock.withLock { self.pendingTasks.removeValue(forKey: taskId) } }
            if Task.isCancelled { return }

            var decodedCallbackPath: String? = nil

            if let rawBody = jsMessage.body as? [String: Any],
                let rawData = rawBody["data"] as? [String: Any],
                let rawCallback = rawData["callbackPath"] as? String,
                rawCallback.isValidCallbackPath
            {
                decodedCallbackPath = rawCallback
            }

            let fallbackOriginAllowed: Bool = {
                guard let url = try? jsMessage.frameInfo.securityOrigin.asURL() else { return false }
                return self.lock.withLock { self.originPolicy.isAllowed(url) }
            }()
            do {
                let message = try self.parseAndValidate(jsMessage)
                decodedCallbackPath = message.payload.callbackPath

                if Task.isCancelled { return }

                self.logger?.logV(
                    source: self,
                    prefix: "handleMessage",
                    message: "Processing [\(message.payload.pluginID):\(message.payload.action)]"
                )

                let pluginKey = WebBridgePluginKey(id: message.payload.pluginID)
                guard let plugin = self.lock.withLock({ self.attachedPluginsByKey[pluginKey] }) else {
                    throw WebBridgeError.general("Unknown plugin: \(message.payload.pluginID)")
                }

                if Task.isCancelled { return }

                let result = try await self.pluginLockRegistry.withLock(key: pluginKey) {
                    await plugin.handle(message)
                }

                if Task.isCancelled { return }

                guard let webView = jsMessage.webView, self.isAttachedToWebView else {
                    self.logger?.logI(source: self, prefix: "handleMessage", message: "WebView detached during processing")
                    return
                }

                let resultJson = result.toResultString(coder: self.coder)
                self.logger?.logV(
                    source: self,
                    prefix: "handleMessage",
                    message: "Completed [\(message.payload.pluginID):\(message.payload.action)]"
                )

                if Task.isCancelled { return }

                await MainActor.run { webView.evaluateJavaScript("\(message.payload.callbackPath)(\(resultJson));") }
            } catch {
                if Task.isCancelled && !(error is CancellationError) { return }

                self.logger?.logW(
                    source: self,
                    prefix: "userContentController",
                    message: "Failed to process WebBridge message",
                    cause: error
                )

                guard let callbackPath = decodedCallbackPath, fallbackOriginAllowed,
                    let webView = jsMessage.webView,
                    self.isAttachedToWebView
                else { return }

                let errorResult: WebBridgePluginResult
                if error is CancellationError {
                    errorResult = WebBridgePluginResult.error(message: "WebBridgeImpl: \(error.localizedDescription)", type: "ABORTED")
                } else {
                    errorResult = WebBridgePluginResult.error(message: "WebBridgeImpl: \(error.localizedDescription)")
                }

                let resultJson = errorResult.toResultString(coder: self.coder)
                if Task.isCancelled { return }
                await MainActor.run { webView.evaluateJavaScript("\(callbackPath)(\(resultJson));") }
            }
        }

        lock.withLock { pendingTasks[taskId] = task }
    }

    private var isAttachedToWebView: Bool {
        lock.withLock { self.isAttached }
    }

    private func parseAndValidate(_ message: WKScriptMessage) throws -> WebBridgePluginMessage {
        guard message.name == Constants.JS_HANDLER_NAME else {
            throw WebBridgeError.general("Unsupported handler \(message.name)")
        }

        guard let messageBody = message.body as? [String: Any],
            let data = messageBody["data"] as? [String: Any],
            let msgWebView = message.webView
        else {
            throw WebBridgeError.general("Invalid message structure")
        }

        if let method = messageBody["method"] as? String {
            if method != "invokeNative" {
                throw WebBridgeError.general("Unsupported method \(method)")
            }
        }

        let payload = try coder.decodeFromJSONValue(JSONValue(from: data), as: WebBridgePluginMessage.Payload.self)

        let trimmedPluginID = payload.pluginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPluginID.isEmpty else {
            throw WebBridgeError.general("pluginID must not be blank")
        }
        let trimmedAction = payload.action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAction.isEmpty else {
            throw WebBridgeError.general("action must not be blank")
        }
        guard payload.callbackPath.isValidCallbackPath else {
            throw WebBridgeError.general("Invalid callbackPath: \(payload.callbackPath)")
        }

        let originURL = try message.frameInfo.securityOrigin.asURL()
        guard message.frameInfo.isMainFrame else {
            throw WebBridgeError.general("Origin \(originURL.originString) not allowed (subframe message)")
        }
        let policy = lock.withLock { self.originPolicy }
        guard policy.isAllowed(originURL) else {
            throw WebBridgeError.general("Origin \(originURL.originString) not allowed")
        }

        let pluginMessage = WebBridgePluginMessage(
            webView: msgWebView,
            sourceOrigin: originURL,
            isMainFrame: message.frameInfo.isMainFrame,
            allowedOriginRules: lock.withLock { self.normalizedOriginRules.isEmpty ? ["*"] : self.normalizedOriginRules },
            payload: payload
        )
        return pluginMessage
    }
}

private actor PluginLockRegistry {
    private struct LockState {
        var isLocked: Bool = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private var states: [WebBridgePluginKey: LockState] = [:]

    func withLock<T: Sendable>(key: WebBridgePluginKey, _ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        await lock(key: key)
        defer { unlock(key: key) }
        try Task.checkCancellation()
        return try await operation()
    }

    private func lock(key: WebBridgePluginKey) async {
        var state = states[key] ?? LockState()
        if !state.isLocked {
            state.isLocked = true
            states[key] = state
            return
        }
        await withCheckedContinuation { continuation in
            state.waiters.append(continuation)
            states[key] = state
        }
    }

    private func unlock(key: WebBridgePluginKey) {
        guard var state = states[key] else { return }
        if !state.waiters.isEmpty {
            let continuation = state.waiters.removeFirst()
            states[key] = state
            continuation.resume()
        } else {
            state.isLocked = false
            states[key] = state
        }
    }
}

extension WebBridgeImpl {
    nonisolated internal static func create(resolver: any DIContainerResolver, initialPlugins: [any WebBridgePlugin]) -> any WebBridge {
        do {
            return WebBridgeImpl(
                plugins: WebBridgePluginRegistryImpl(initialPlugins: initialPlugins),
                appConfigProvider: try resolver.getOrThrow(type: (any AppConfigProvider).self),
                coder: try resolver.getOrThrow(type: (any JSONCoder).self),
                logger: resolver.getOrNil(type: OwnIDLogRouter.self)
            )
        } catch {
            return FailedWebBridge(logger: resolver.getOrNil(type: OwnIDLogRouter.self), error: error)
        }
    }
}

private final class FailedWebBridge: WebBridge, @unchecked Sendable {
    private let logger: OwnIDLogRouter?
    private let error: any Error
    let plugins: any WebBridgePluginRegistry

    init(logger: OwnIDLogRouter?, error: any Error) {
        self.logger = logger
        self.error = error
        self.plugins = FailedWebBridgePluginRegistry(logger: logger, error: error)
    }

    func attach(webView: WKWebView, allowedOriginRules: Set<String>) -> WebBridgeError? {
        logger?.logW(
            source: self,
            prefix: "attach",
            message: "WebBridge initialization failed: \(error.localizedDescription)",
            cause: error
        )
        return .general("WebBridge initialization failed", error)
    }

    func detach() {
        logger?.logD(source: self, prefix: "detach", message: "No-op WebBridge")

    }
}

private final class FailedWebBridgePluginRegistry: WebBridgePluginRegistry, @unchecked Sendable {
    private let logger: OwnIDLogRouter?
    private let error: any Error

    init(logger: OwnIDLogRouter?, error: any Error) {
        self.logger = logger
        self.error = error
    }

    func add(plugin: any WebBridgePlugin) {
        logger?.logD(source: self, prefix: "add", message: "No-op: \(plugin.key). Initialization failed: \(error.localizedDescription)")
    }

    func remove(key: WebBridgePluginKey) {
        logger?.logD(source: self, prefix: "remove", message: "No-op: \(key). Initialization failed: \(error.localizedDescription)")
    }

    func get(key: WebBridgePluginKey) -> (any WebBridgePlugin)? {
        logger?.logD(source: self, prefix: "get", message: "No-op: \(key). Initialization failed: \(error.localizedDescription)")
        return nil
    }

    func snapshot() -> [any WebBridgePlugin] { [] }
}

extension WKSecurityOrigin {
    fileprivate func asURL() throws -> URL {
        guard !host.isEmpty else { throw URLError(.unsupportedURL) }
        var components = URLComponents()
        components.scheme = self.protocol
        components.host = host
        let defaultHTTP = (self.protocol == "http" && port == 80)
        let defaultHTTPS = (self.protocol == "https" && port == 443)
        if port != 0, !defaultHTTP, !defaultHTTPS {
            components.port = port
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}

extension URL {
    fileprivate var originString: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self.absoluteString }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string ?? self.absoluteString
    }
}

extension String {
    private enum RegexHolder {
        static let callbackPath = try! NSRegularExpression(pattern: #"^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$"#)
    }

    fileprivate var isValidCallbackPath: Bool {
        let range = NSRange(location: 0, length: utf16.count)
        return RegexHolder.callbackPath.firstMatch(in: self, range: range) != nil
    }
}
