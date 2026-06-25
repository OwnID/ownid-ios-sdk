import Foundation
import Testing
import WebKit

@_spi(OwnIDInternal) @testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct WebBridgeAttachmentRuntimeTests {

    @Test func `Attach installs document start main frame bridge script with advertised namespaces`() throws {
        let bridge = makeBridge(plugins: [
            RuntimeWebBridgePlugin(id: "storage", actions: ["getLastUser"]),
            RuntimeWebBridgePlugin(id: "metadata", actions: ["get"]),
        ])
        let webView = makeWebBridgeTestWebView()
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        let error = bridge.attach(webView: webView, allowedOriginRules: [" Example.com ", "https://bad.example/path"])

        #expect(error == nil)
        let script = try singleUserScript(from: webView)
        #expect(script.injectionTime == .atDocumentStart)
        #expect(script.isForMainFrameOnly)
        #expect(script.source.contains("__ownidNativeBridgeHandler"))
        #expect(
            try injectedNamespaces(from: script) == [
                "STORAGE": ["getLastUser"],
                "METADATA": ["get"],
            ]
        )
    }

    @Test func `Attach fails closed without effective origins and keeps bridge reusable`() throws {
        let bridge = makeBridge(plugins: [RuntimeWebBridgePlugin(id: "storage")])
        let failedWebView = makeWebBridgeTestWebView()

        let firstError = bridge.attach(webView: failedWebView, allowedOriginRules: [])

        #expect(firstError?.errorDescription?.contains("Error attaching bridge") == true)
        #expect(failedWebView.configuration.userContentController.userScripts.isEmpty)

        let attachedWebView = makeWebBridgeTestWebView()
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(failedWebView)
            tearDownWebBridgeTestWebView(attachedWebView)
        }
        let secondError = bridge.attach(webView: attachedWebView, allowedOriginRules: ["example.com"])

        #expect(secondError == nil)
        #expect(attachedWebView.configuration.userContentController.userScripts.count == 1)
    }

    @Test func `Detached bridge cannot be attached again and leaves prior scripts as WebKit-owned artifacts`() throws {
        let bridge = makeBridge(plugins: [RuntimeWebBridgePlugin(id: "storage")])
        let firstWebView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(firstWebView) }

        #expect(bridge.attach(webView: firstWebView, allowedOriginRules: ["example.com"]) == nil)
        bridge.detach()

        #expect(firstWebView.configuration.userContentController.userScripts.count == 1)

        let secondWebView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(secondWebView) }
        let secondError = bridge.attach(webView: secondWebView, allowedOriginRules: ["example.com"])

        #expect(secondError?.errorDescription?.contains("Error attaching bridge") == true)
        #expect(secondWebView.configuration.userContentController.userScripts.isEmpty)
    }

    @Test func `Attached bridge script uses plugin snapshot while namespace factory edits affect later bridges`() throws {
        let store = WebBridgePluginFactoryStoreImpl()
        let namespace = makeNamespace(factoryStore: store)
        let storageKey = WebBridgePluginKey(id: "storage")
        let metadataKey = WebBridgePluginKey(id: "metadata")

        store.register(key: storageKey) { RuntimeWebBridgePlugin(id: "storage", actions: ["original"]) }
        let firstBridge = namespace.create()
        let firstWebView = makeWebBridgeTestWebView()
        defer {
            firstBridge.detach()
            tearDownWebBridgeTestWebView(firstWebView)
        }

        #expect(firstBridge.attach(webView: firstWebView, allowedOriginRules: ["example.com"]) == nil)

        firstBridge.plugins.remove(key: storageKey)
        firstBridge.plugins.add(plugin: RuntimeWebBridgePlugin(id: "metadata", actions: ["late"]))
        store.register(key: metadataKey) { RuntimeWebBridgePlugin(id: "metadata", actions: ["future"]) }

        #expect(
            try injectedNamespaces(from: singleUserScript(from: firstWebView)) == [
                "STORAGE": ["original"]
            ]
        )

        let secondBridge = namespace.create()
        let secondWebView = makeWebBridgeTestWebView()
        defer {
            secondBridge.detach()
            tearDownWebBridgeTestWebView(secondWebView)
        }

        #expect(secondBridge.attach(webView: secondWebView, allowedOriginRules: ["example.com"]) == nil)
        #expect(
            try injectedNamespaces(from: singleUserScript(from: secondWebView)) == [
                "STORAGE": ["original"],
                "METADATA": ["future"],
            ]
        )
    }

    @Test func `Allowed main frame message invokes matching plugin and evaluates callback result`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(
            id: "echo",
            result: .success(JSONValue(["handled": "yes"]))
        )
        let otherPlugin = RecordingRuntimeWebBridgePlugin(id: "other")
        let bridge = makeBridge(plugins: [plugin, otherPlugin])
        let callbackProbe = WebBridgeScriptCallbackProbe()
        let webView = makeWebBridgeTestWebView {
            $0.userContentController.add(callbackProbe, name: WebBridgeScriptCallbackProbe.handlerName)
        }
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://login.example.test/start")!, in: webView)

        try await evaluateWebBridgeTestJavaScript(
            """
            window.__ownidNativeBridge.invokeNative(
                'ECHO',
                'get',
                'OwnID.callback',
                '{"value":"request"}'
            );
            true;
            """,
            in: webView
        )

        let callback = try await withFlowTimeout("wait for WebBridge callback") {
            await callbackProbe.waitForMessage()
        }
        let payload = try callbackPayload(from: callback)
        let message = try await withFlowTimeout("wait for WebBridge plugin message") {
            await plugin.waitForMessage()
        }

        #expect(payload["handled"] == .string("yes"))
        #expect(message.pluginID == "ECHO")
        #expect(message.action == "get")
        #expect(message.params == #"{"value":"request"}"#)
        #expect(message.sourceScheme == "https")
        #expect(message.sourceHost == "login.example.test")
        #expect(message.isMainFrame)
        #expect(message.allowedOriginRules == ["https://login.example.test"])
        #expect(plugin.invocationCount == 1)
        #expect(otherPlugin.invocationCount == 0)
    }

    @Test func `Unknown plugin evaluates safe callback error without invoking registered plugins`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin])
        let callbackProbe = WebBridgeScriptCallbackProbe()
        let webView = makeWebBridgeTestWebView {
            $0.userContentController.add(callbackProbe, name: WebBridgeScriptCallbackProbe.handlerName)
        }
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://login.example.test/start")!, in: webView)

        try await evaluateWebBridgeTestJavaScript(
            """
            window.__ownidNativeBridge.invokeNative('MISSING', 'get', 'OwnID.callback', null);
            true;
            """,
            in: webView
        )

        let callback = try await withFlowTimeout("wait for unknown-plugin callback") {
            await callbackProbe.waitForMessage()
        }
        let payload = try callbackPayload(from: callback)

        #expect(payload["error"]?["type"] == .string("UNKNOWN"))
        #expect(payload["error"]?["message"]?.stringValue?.contains("Unknown plugin: MISSING") == true)
        #expect(plugin.invocationCount == 0)
    }

    @Test func `Unsupported method evaluates safe callback error without invoking plugin`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin])
        let callbackProbe = WebBridgeScriptCallbackProbe()
        let webView = makeWebBridgeTestWebView {
            $0.userContentController.add(callbackProbe, name: WebBridgeScriptCallbackProbe.handlerName)
        }
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://login.example.test/start")!, in: webView)

        try await evaluateWebBridgeTestJavaScript(
            """
            window.webkit.messageHandlers.__ownidNativeBridgeHandler.postMessage({
                method: 'unsupported',
                data: { pluginId: 'ECHO', action: 'get', callbackPath: 'OwnID.callback' }
            });
            true;
            """,
            in: webView
        )

        let callback = try await withFlowTimeout("wait for unsupported-method callback") {
            await callbackProbe.waitForMessage()
        }
        let payload = try callbackPayload(from: callback)

        #expect(payload["error"]?["type"] == .string("UNKNOWN"))
        #expect(payload["error"]?["message"]?.stringValue?.contains("Unsupported method unsupported") == true)
        #expect(plugin.invocationCount == 0)
    }

    @Test func `Invalid callback path is rejected before plugin dispatch`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let logSink = LogCapture()
        let bridge = makeBridge(plugins: [plugin], logger: webBridgeTestLogRouter(sink: logSink))
        let webView = makeWebBridgeTestWebView()
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://login.example.test/start")!, in: webView)

        try await evaluateWebBridgeTestJavaScript(
            """
            window.webkit.messageHandlers.__ownidNativeBridgeHandler.postMessage({
                method: 'invokeNative',
                data: { pluginId: 'ECHO', action: 'get', callbackPath: 'OwnID.callbacks[0]' }
            });
            true;
            """,
            in: webView
        )

        let entry = try await logSink.waitForEntry(
            containing: "Invalid callbackPath",
            timeoutDescription: "invalid callback rejection log"
        )
        #expect(entry.message.contains("Failed to process WebBridge message"))
        #expect(entry.causeDescription?.contains("Invalid callbackPath") == true)
        #expect(plugin.invocationCount == 0)
    }

    @Test func `Disallowed origin is rejected before plugin dispatch`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let logSink = LogCapture()
        let bridge = makeBridge(plugins: [plugin], logger: webBridgeTestLogRouter(sink: logSink))
        let webView = makeWebBridgeTestWebView()
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://allowed.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://evil.example.test/start")!, in: webView)

        try await evaluateWebBridgeTestJavaScript(
            """
            window.__ownidNativeBridge.invokeNative('ECHO', 'get', 'OwnID.callback', null);
            true;
            """,
            in: webView
        )

        let entry = try await logSink.waitForEntry(
            containing: "not allowed",
            timeoutDescription: "disallowed origin rejection log"
        )
        #expect(entry.message.contains("Failed to process WebBridge message"))
        #expect(entry.causeDescription?.contains("not allowed") == true)
        #expect(plugin.invocationCount == 0)
    }

    @Test func `Plugin error result evaluates safe callback error`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(
            id: "echo",
            result: .error(message: "plugin refused", type: "PLUGIN_REFUSED")
        )
        let callbackProbe = WebBridgeScriptCallbackProbe()
        let bridge = makeBridge(plugins: [plugin])
        let webView = makeWebBridgeTestWebView {
            $0.userContentController.add(callbackProbe, name: WebBridgeScriptCallbackProbe.handlerName)
        }
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://login.example.test/start")!, in: webView)

        try await invokeWebBridgePlugin(pluginID: "ECHO", action: "get", in: webView)

        let callback = try await withFlowTimeout("wait for plugin error callback") {
            await callbackProbe.waitForMessage()
        }
        let payload = try callbackPayload(from: callback)
        #expect(payload["error"]?["type"] == .string("PLUGIN_REFUSED"))
        #expect(payload["error"]?["message"] == .string("plugin refused"))
        #expect(plugin.invocationCount == 1)
    }

    @Test func `Detach cancels in-flight plugin work before callback evaluation`() async throws {
        let plugin = GatedRuntimeWebBridgePlugin(id: "delayed")
        let bridge = makeBridge(plugins: [plugin])
        let webView = makeWebBridgeTestWebView()
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(
            webBridgeCountingCallbackHTML,
            baseURL: URL(string: "https://login.example.test/start")!,
            in: webView
        )

        try await invokeWebBridgePlugin(pluginID: "DELAYED", action: "get", in: webView)
        let firstStart = try await withFlowTimeout("wait for delayed plugin start") {
            await plugin.waitForStartCount(1)
        }

        bridge.detach()
        let cancelCount = try await withFlowTimeout("wait for delayed plugin cancellation") {
            await plugin.waitForCancelCount(1)
        }
        await plugin.releaseNext()
        await settleWebBridgeTasks()
        let callbackCount = try await callbackCount(in: webView)

        #expect(firstStart == 1)
        #expect(cancelCount == 1)
        #expect(callbackCount == 0)
    }

    @Test func `Messages are serialized per plugin key while different plugins proceed concurrently`() async throws {
        let slow = GatedRuntimeWebBridgePlugin(id: "slow")
        let other = GatedRuntimeWebBridgePlugin(id: "other")
        let bridge = makeBridge(plugins: [slow, other])
        let webView = makeWebBridgeTestWebView()
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(
            webBridgeCountingCallbackHTML,
            baseURL: URL(string: "https://login.example.test/start")!,
            in: webView
        )

        try await invokeWebBridgePlugin(pluginID: "SLOW", action: "first", in: webView)
        #expect(try await withFlowTimeout("wait for first slow start") { await slow.waitForStartCount(1) } == 1)

        try await invokeWebBridgePlugin(pluginID: "SLOW", action: "second", in: webView)
        await settleWebBridgeTasks()
        #expect(await slow.startCount() == 1)

        try await invokeWebBridgePlugin(pluginID: "OTHER", action: "parallel", in: webView)
        #expect(try await withFlowTimeout("wait for other start") { await other.waitForStartCount(1) } == 1)
        #expect(await slow.startCount() == 1)

        await slow.releaseNext()
        #expect(try await withFlowTimeout("wait for second slow start") { await slow.waitForStartCount(2) } == 2)
        await slow.releaseNext()
        await other.releaseNext()
        await settleWebBridgeTasks()

        #expect(await slow.invocationActionsSnapshot() == ["first", "second"])
        #expect(await other.invocationActionsSnapshot() == ["parallel"])
    }

    private func makeBridge(plugins: [any WebBridgePlugin], logger: OwnIDLogRouter? = nil) -> any WebBridge {
        WebBridgeImpl(
            plugins: WebBridgePluginRegistryImpl(initialPlugins: plugins),
            appConfigProvider: SilentAppConfigProvider(),
            coder: JSONCoderImpl(),
            logger: logger
        )
    }
}

struct WebBridgeFactoryRuntimeTests {

    @Test func `Namespace create builds fresh plugin instances for each bridge`() throws {
        let store = WebBridgePluginFactoryStoreImpl()
        let namespace = makeNamespace(factoryStore: store)
        let storageKey = WebBridgePluginKey(id: "storage")
        let metadataKey = WebBridgePluginKey(id: "metadata")
        var storageFactoryCalls = 0
        var metadataFactoryCalls = 0

        store.register(key: storageKey) {
            storageFactoryCalls += 1
            return RuntimeWebBridgePlugin(id: "storage", marker: "storage-\(storageFactoryCalls)")
        }
        store.register(key: metadataKey) {
            metadataFactoryCalls += 1
            return RuntimeWebBridgePlugin(id: "metadata", marker: "metadata-\(metadataFactoryCalls)")
        }

        let firstBridge = namespace.create()
        let secondBridge = namespace.create()

        let firstStorage = try #require(firstBridge.plugins.get(key: storageKey) as? RuntimeWebBridgePlugin)
        let firstMetadata = try #require(firstBridge.plugins.get(key: metadataKey) as? RuntimeWebBridgePlugin)
        let secondStorage = try #require(secondBridge.plugins.get(key: storageKey) as? RuntimeWebBridgePlugin)
        let secondMetadata = try #require(secondBridge.plugins.get(key: metadataKey) as? RuntimeWebBridgePlugin)

        #expect(firstStorage !== secondStorage)
        #expect(firstMetadata !== secondMetadata)
        #expect(firstStorage.marker == "storage-1")
        #expect(firstMetadata.marker == "metadata-1")
        #expect(secondStorage.marker == "storage-2")
        #expect(secondMetadata.marker == "metadata-2")
    }

    @Test func `Namespace create skips throwing and mismatched plugin factories with warnings`() throws {
        let store = WebBridgePluginFactoryStoreImpl()
        let logSink = LogCapture()
        let namespace = makeNamespace(factoryStore: store, logger: webBridgeTestLogRouter(sink: logSink))
        let throwingKey = WebBridgePluginKey(id: "throwing")
        let mismatchedKey = WebBridgePluginKey(id: "expected")
        let validKey = WebBridgePluginKey(id: "valid")

        store.register(key: throwingKey) { throw RuntimeWebBridgeFactoryError.expected }
        store.register(key: mismatchedKey) { RuntimeWebBridgePlugin(id: "actual", marker: "mismatched") }
        store.register(key: validKey) { RuntimeWebBridgePlugin(id: "valid", marker: "valid") }

        let bridge = namespace.create()

        #expect(try pluginMarkers(from: bridge.plugins.snapshot()) == ["valid"])
        #expect(logSink.messages.contains { $0.contains("Failed to instantiate WebBridge plugin THROWING") })
        #expect(logSink.messages.contains { $0.contains("instantiated plugin key ACTUAL does not match definition key EXPECTED") })
    }
}

@MainActor
private func singleUserScript(from webView: WKWebView) throws -> WKUserScript {
    let scripts = webView.configuration.userContentController.userScripts
    #expect(scripts.count == 1)
    return try #require(scripts.first)
}

@MainActor
private func injectedNamespaces(from script: WKUserScript) throws -> [String: [String]] {
    let prefix = "getNamespaces: function getNamespaces() { return '"
    let suffix = "'; },"
    let prefixRange = try #require(script.source.range(of: prefix))
    let remaining = script.source[prefixRange.upperBound...]
    let suffixRange = try #require(remaining.range(of: suffix))
    let json = String(remaining[..<suffixRange.lowerBound])
    let data = try #require(json.data(using: .utf8))
    return try JSONDecoder().decode([String: [String]].self, from: data)
}

private func makeNamespace(
    factoryStore: WebBridgePluginFactoryStoreImpl,
    logger: OwnIDLogRouter? = nil
) -> OwnIDWebBridge {
    let container = DIContainerImpl(scopeName: "webbridge-runtime-tests")
    container.register((any AppConfigProvider).self, instance: SilentAppConfigProvider())
    container.register((any JSONCoder).self, instance: JSONCoderImpl())
    if let logger {
        container.register(OwnIDLogRouter.self, instance: logger)
    }
    return OwnIDWebBridge(container: container, pluginFactoryStore: factoryStore)
}

private func pluginMarkers(from plugins: [any WebBridgePlugin]) throws -> [String] {
    try plugins.map { plugin in
        try #require(plugin as? RuntimeWebBridgePlugin).marker
    }
}

private let webBridgeRuntimeHTML = """
    <html>
      <body>
        <script>
          window.OwnID = {
            callback: function callback(value) {
              window.webkit.messageHandlers.__ownidTestCallback.postMessage(JSON.stringify(value));
            }
          };
        </script>
      </body>
    </html>
    """

private let webBridgeCountingCallbackHTML = """
    <html>
      <body>
        <script>
          window.OwnID = {
            callbackCount: 0,
            callback: function callback(value) {
              window.OwnID.callbackCount += 1;
            }
          };
        </script>
      </body>
    </html>
    """

@MainActor
private func invokeWebBridgePlugin(pluginID: String, action: String, in webView: WKWebView) async throws {
    try await evaluateWebBridgeTestJavaScript(
        """
        window.__ownidNativeBridge.invokeNative(
            '\(pluginID)',
            '\(action)',
            'OwnID.callback',
            '{"value":"request"}'
        );
        true;
        """,
        in: webView
    )
}

@MainActor
private func callbackCount(in webView: WKWebView) async throws -> Int {
    let result = try await evaluateWebBridgeTestJavaScript("String(window.OwnID.callbackCount || 0);", in: webView)
    return Int(result ?? "0") ?? 0
}

private func settleWebBridgeTasks() async {
    for _ in 0..<5 {
        await Task.yield()
    }
}

private func callbackPayload(from callback: String) throws -> JSONValue {
    try JSONCoderImpl().decodeFromString(callback, as: JSONValue.self)
}

private struct RuntimeWebBridgeReceivedMessage: Sendable {
    let pluginID: String
    let action: String
    let params: String?
    let sourceScheme: String?
    let sourceHost: String?
    let isMainFrame: Bool
    let allowedOriginRules: Set<String>
}

private final class RuntimeWebBridgePlugin: WebBridgePlugin, @unchecked Sendable {
    let key: WebBridgePluginKey
    let actions: [String]
    let marker: String

    init(id: String, actions: [String] = ["get"], marker: String? = nil) {
        self.key = WebBridgePluginKey(id: id)
        self.actions = actions
        self.marker = marker ?? self.key.id
    }

    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        .success(JSONValue(marker))
    }
}

private final class RecordingRuntimeWebBridgePlugin: WebBridgePlugin, @unchecked Sendable {
    let key: WebBridgePluginKey
    let actions: [String]

    private let result: WebBridgePluginResult
    private let message = CapturedFlowValue<RuntimeWebBridgeReceivedMessage>()
    private let lock = NSLock()
    private var count = 0

    init(
        id: String,
        actions: [String] = ["get"],
        result: WebBridgePluginResult = .success(JSONValue(["handled": "default"]))
    ) {
        self.key = WebBridgePluginKey(id: id)
        self.actions = actions
        self.result = result
    }

    var invocationCount: Int {
        lock.withLock { count }
    }

    func waitForMessage() async -> RuntimeWebBridgeReceivedMessage {
        await message.wait()
    }

    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        lock.withLock { count += 1 }
        self.message.set(
            RuntimeWebBridgeReceivedMessage(
                pluginID: message.payload.pluginID,
                action: message.payload.action,
                params: message.payload.params,
                sourceScheme: message.sourceOrigin.scheme,
                sourceHost: message.sourceOrigin.host,
                isMainFrame: message.isMainFrame,
                allowedOriginRules: message.allowedOriginRules
            )
        )
        return result
    }
}

private actor GatedRuntimeWebBridgePlugin: WebBridgePlugin {
    nonisolated let key: WebBridgePluginKey
    nonisolated let actions: [String]

    private var invocationActions: [String] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Int, Never>)] = []
    private var cancelCountValue = 0
    private var cancelWaiters: [(count: Int, continuation: CheckedContinuation<Int, Never>)] = []

    init(id: String, actions: [String] = ["first", "second", "parallel", "get"]) {
        self.key = WebBridgePluginKey(id: id)
        self.actions = actions
    }

    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        invocationActions.append(message.payload.action)
        resumeStartWaiters()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }

        if Task.isCancelled {
            return .error(message: "canceled", type: "ABORTED")
        }
        return .success(JSONValue(["action": message.payload.action]))
    }

    func releaseNext() {
        guard !releaseContinuations.isEmpty else { return }
        releaseContinuations.removeFirst().resume()
    }

    func waitForStartCount(_ count: Int) async -> Int {
        if invocationActions.count >= count { return invocationActions.count }
        return await withCheckedContinuation { continuation in
            startWaiters.append((count: count, continuation: continuation))
        }
    }

    func startCount() -> Int {
        invocationActions.count
    }

    func invocationActionsSnapshot() -> [String] {
        invocationActions
    }

    func waitForCancelCount(_ count: Int) async -> Int {
        if cancelCountValue >= count { return cancelCountValue }
        return await withCheckedContinuation { continuation in
            cancelWaiters.append((count: count, continuation: continuation))
        }
    }

    private func recordCancellation() {
        cancelCountValue += 1
        let ready = cancelWaiters.filter { cancelCountValue >= $0.count }
        cancelWaiters.removeAll { cancelCountValue >= $0.count }
        for waiter in ready {
            waiter.continuation.resume(returning: cancelCountValue)
        }
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { invocationActions.count >= $0.count }
        startWaiters.removeAll { invocationActions.count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume(returning: invocationActions.count)
        }
    }
}

private final class SilentAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    func getOrFetchConfig() async throws -> AppConfig {
        .default
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private enum RuntimeWebBridgeFactoryError: Error {
    case expected
}
