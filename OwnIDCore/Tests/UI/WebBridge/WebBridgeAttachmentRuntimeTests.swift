import Foundation
import Testing
import WebKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: WB-BRIDGE-040, WB-BRIDGE-050, WB-BRIDGE-060, WB-BRIDGE-070, WB-BRIDGE-090, WB-BRIDGE-100, WB-BRIDGE-110, WB-BRIDGE-340
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

    @Test func `Attach uses server origins when explicit origins are empty`() async throws {
        let provider = ControlledWebBridgeAppConfigProvider()
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin], appConfigProvider: provider)
        let webView = makeWebBridgeTestWebView()
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://server.example.test"])
        )

        #expect(bridge.attach(webView: webView) == nil)
        try await loadAndInvokeEcho(in: webView, origin: "https://server.example.test")

        let message = try await plugin.waitForMessage()
        #expect(message.allowedOriginRules == ["https://server.example.test"])
    }

    @Test func `Attach unions explicit and server origins`() async throws {
        let provider = ControlledWebBridgeAppConfigProvider()
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin], appConfigProvider: provider)
        let webView = makeWebBridgeTestWebView()
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://server.example.test"])
        )

        #expect(
            bridge.attach(
                webView: webView,
                allowedOriginRules: ["https://explicit.example.test"]
            ) == nil
        )
        try await loadAndInvokeEcho(in: webView, origin: "https://explicit.example.test")

        let message = try await plugin.waitForMessage()
        #expect(
            message.allowedOriginRules == [
                "https://explicit.example.test",
                "https://server.example.test",
            ]
        )
    }

    @Test func `Attach snapshots the latest observed server origins`() async throws {
        let provider = ControlledWebBridgeAppConfigProvider()
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin], appConfigProvider: provider)
        let webView = makeWebBridgeTestWebView()
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://stale.example.test"])
        )
        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://latest.example.test"])
        )

        #expect(bridge.attach(webView: webView) == nil)
        try await loadAndInvokeEcho(in: webView, origin: "https://latest.example.test")

        let message = try await plugin.waitForMessage()
        #expect(message.allowedOriginRules == ["https://latest.example.test"])
    }

    @Test func `Server config observed after attach does not mutate captured origins`() async throws {
        let provider = ControlledWebBridgeAppConfigProvider()
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let logSink = LogCapture()
        let bridge = makeBridge(
            plugins: [plugin],
            logger: webBridgeTestLogRouter(sink: logSink),
            appConfigProvider: provider
        )
        let webView = makeWebBridgeTestWebView()
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://initial.example.test"])
        )
        #expect(bridge.attach(webView: webView) == nil)
        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://late.example.test"])
        )

        try await loadAndInvokeEcho(in: webView, origin: "https://initial.example.test")
        let message = try await plugin.waitForMessage()
        #expect(message.allowedOriginRules == ["https://initial.example.test"])

        try await loadAndInvokeEcho(in: webView, origin: "https://late.example.test")
        let rejection = try await logSink.waitForEntry(
            containing: "not allowed",
            timeoutDescription: "late server origin rejection"
        )
        #expect(rejection.causeDescription?.contains("not allowed") == true)
        #expect(plugin.invocationCount == 1)
    }

    @Test func `Attach can retry after server origins are observed`() async throws {
        let provider = ControlledWebBridgeAppConfigProvider()
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin], appConfigProvider: provider)
        let webView = makeWebBridgeTestWebView()
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        let initialError = bridge.attach(webView: webView)
        #expect(initialError?.errorDescription?.contains("Error attaching bridge") == true)
        #expect(webView.configuration.userContentController.userScripts.isEmpty)

        await provider.yieldAndWaitForObservation(
            Self.appConfig(allowedOrigins: ["https://retry.example.test"])
        )

        #expect(bridge.attach(webView: webView) == nil)
        try await loadAndInvokeEcho(in: webView, origin: "https://retry.example.test")

        let message = try await plugin.waitForMessage()
        #expect(message.allowedOriginRules == ["https://retry.example.test"])
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

        #expect(secondError?.errorDescription?.contains("WebBridge instance already used") == true)
        #expect(secondWebView.configuration.userContentController.userScripts.isEmpty)
    }

    @Test func `Bridge-local UI context follows removal and rehosting before closing on detach`() throws {
        let provider = WebBridgeUIContextProviderImpl()
        let bridge = makeBridge(plugins: [], uiContextProvider: provider)
        let webView = makeWebBridgeTestWebView()
        let firstHost = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            firstHost.tearDown()
        }

        guard case .failure(let initialError) = provider.current() else {
            Issue.record("Expected an unavailable context before WebBridge attachment")
            return
        }
        let initialResolutionError = try #require(initialError as? UIContextResolutionError)
        #expect(initialResolutionError.reason == .unavailable)

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)

        guard case .windowAndController(let window, let controller) = provider.current() else {
            Issue.record("Expected the attached WebView window and controller")
            return
        }
        #expect(window === firstHost.window)
        #expect(controller === firstHost.controller)

        firstHost.tearDown()
        guard case .failure(let removedError) = provider.current() else {
            Issue.record("Expected unavailable context while the attached WebView has no window")
            return
        }
        #expect((try #require(removedError as? UIContextResolutionError)).reason == .unavailable)

        let secondHost = WebBridgeTestWebViewHost(webView)
        defer { secondHost.tearDown() }
        guard case .windowAndController(let rehostedWindow, let rehostedController) = provider.current() else {
            Issue.record("Expected context from the rehosted attached WebView")
            return
        }
        #expect(rehostedWindow === secondHost.window)
        #expect(rehostedWindow !== firstHost.window)
        #expect(rehostedController === secondHost.controller)

        bridge.detach()
        guard case .failure(let closedError) = provider.current() else {
            Issue.record("Expected a closed context after WebBridge detach")
            return
        }
        let ownerClosedError = try #require(closedError as? UIContextResolutionError)
        #expect(ownerClosedError.reason == .ownerClosed)
    }

    @Test func `Attached WebView deallocation closes local context`() async throws {
        let provider = WebBridgeUIContextProviderImpl()
        let bridge = makeBridge(plugins: [], uiContextProvider: provider)
        weak var releasedWebView: WKWebView?

        autoreleasepool {
            let webView = makeWebBridgeTestWebView()
            releasedWebView = webView
            #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        }

        for _ in 0..<500 {
            guard releasedWebView != nil else { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(releasedWebView == nil)

        for _ in 0..<500 {
            guard case .failure(let error) = provider.current(),
                (error as? UIContextResolutionError)?.reason != .ownerClosed
            else { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .failure(let closedError) = provider.current() else {
            Issue.record("Expected owner-closed context after attached WebView deallocation")
            return
        }
        #expect((try #require(closedError as? UIContextResolutionError)).reason == .ownerClosed)
    }

    @Test func `Bridge-local UI context can be rebound after a failed attach attempt`() throws {
        let provider = WebBridgeUIContextProviderImpl()
        let firstWebView = makeWebBridgeTestWebView()
        let secondWebView = makeWebBridgeTestWebView()
        let secondHost = WebBridgeTestWebViewHost(secondWebView)
        defer {
            provider.close()
            tearDownWebBridgeTestWebView(firstWebView)
            tearDownWebBridgeTestWebView(secondWebView)
            secondHost.tearDown()
        }

        try provider.bind(webView: firstWebView)
        provider.resetAfterFailedAttach()
        guard case .failure(let resetError) = provider.current() else {
            Issue.record("Expected an unavailable context after failed-attach reset")
            return
        }
        #expect((try #require(resetError as? UIContextResolutionError)).reason == .unavailable)

        try provider.bind(webView: secondWebView)
        guard case .windowAndController(let window, _) = provider.current() else {
            Issue.record("Expected the rebound WebView window")
            return
        }
        #expect(window === secondHost.window)
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
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
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

        let callback = try await callbackProbe.waitForMessage("wait for WebBridge callback")
        let payload = try callbackPayload(from: callback)
        let message = try await plugin.waitForMessage()

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

    @Test func `Shared content controller accepts messages only from the attached WebView`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(
            id: "echo",
            result: .success(JSONValue(["handled": "yes"]))
        )
        let bridge = makeBridge(plugins: [plugin])
        let sharedUserContentController = WKUserContentController()
        let attachedWebView = makeWebBridgeTestWebView {
            $0.userContentController = sharedUserContentController
        }
        let foreignWebView = makeWebBridgeTestWebView {
            $0.userContentController = sharedUserContentController
        }
        let attachedHost = WebBridgeTestWebViewHost(attachedWebView)
        let foreignHost = WebBridgeTestWebViewHost(foreignWebView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(attachedWebView)
            tearDownWebBridgeTestWebView(foreignWebView)
            attachedHost.tearDown()
            foreignHost.tearDown()
        }

        #expect(bridge.attach(webView: attachedWebView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(
            webBridgeCountingCallbackHTML,
            baseURL: URL(string: "https://login.example.test/attached")!,
            in: attachedWebView
        )
        try await loadWebBridgeTestHTML(
            webBridgeCountingCallbackHTML,
            baseURL: URL(string: "https://login.example.test/foreign")!,
            in: foreignWebView
        )

        try await invokeWebBridgePlugin(pluginID: "ECHO", action: "get", in: foreignWebView)
        try await invokeWebBridgePlugin(pluginID: "ECHO", action: "get", in: attachedWebView)

        _ = try await plugin.waitForMessage()
        try await withTestTimeout("attached WebView callback") {
            while try await callbackCount(in: attachedWebView) != 1 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        #expect(plugin.invocationCount == 1)
        #expect(try await callbackCount(in: foreignWebView) == 0)
        #expect(try await callbackCount(in: attachedWebView) == 1)
    }

    @Test func `Unknown plugin evaluates safe callback error without invoking registered plugins`() async throws {
        let plugin = RecordingRuntimeWebBridgePlugin(id: "echo")
        let bridge = makeBridge(plugins: [plugin])
        let callbackProbe = WebBridgeScriptCallbackProbe()
        let webView = makeWebBridgeTestWebView {
            $0.userContentController.add(callbackProbe, name: WebBridgeScriptCallbackProbe.handlerName)
        }
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
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

        let callback = try await callbackProbe.waitForMessage("wait for unknown-plugin callback")
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
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
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

        let callback = try await callbackProbe.waitForMessage("wait for unsupported-method callback")
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
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
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
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
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
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(webBridgeRuntimeHTML, baseURL: URL(string: "https://login.example.test/start")!, in: webView)

        try await invokeWebBridgePlugin(pluginID: "ECHO", action: "get", in: webView)

        let callback = try await callbackProbe.waitForMessage("wait for plugin error callback")
        let payload = try callbackPayload(from: callback)
        #expect(payload["error"]?["type"] == .string("PLUGIN_REFUSED"))
        #expect(payload["error"]?["message"] == .string("plugin refused"))
        #expect(plugin.invocationCount == 1)
    }

    @Test func `Detach cancels in-flight plugin work before callback evaluation`() async throws {
        let plugin = GatedRuntimeWebBridgePlugin(id: "delayed")
        var bridge: WebBridgeImpl? = makeBridge(plugins: [plugin])
        let lifetime = WebBridgeTestWeakReference(bridge)
        let webView = makeWebBridgeTestWebView()
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge?.detach()
            Task { await plugin.releaseAllForTeardown() }
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        #expect(bridge?.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(
            webBridgeCountingCallbackHTML,
            baseURL: URL(string: "https://login.example.test/start")!,
            in: webView
        )

        try await invokeWebBridgePlugin(pluginID: "DELAYED", action: "get", in: webView)
        let firstStart = try await plugin.waitForStartCount(1)

        bridge?.detach()
        let cancelCount = try await plugin.waitForCancelCount(1)
        await plugin.releaseNext()
        bridge = nil
        try await withTestTimeout("WebBridge detached handler release") { @MainActor in
            while lifetime.bridge != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        let callbackCount = try await callbackCount(in: webView)

        #expect(firstStart == 1)
        #expect(cancelCount == 1)
        #expect(callbackCount == 0)
    }

    @Test func `Messages are serialized per plugin key while different plugins proceed concurrently`() async throws {
        let events = FlowLocked<[String]>([])
        let slow = GatedRuntimeWebBridgePlugin(id: "slow", events: events)
        let other = GatedRuntimeWebBridgePlugin(id: "other", events: events)
        let callbacks = WebBridgeScriptCallbackProbe()
        let bridge = makeBridge(plugins: [slow, other])
        let webView = makeWebBridgeTestWebView {
            $0.userContentController.add(callbacks, name: WebBridgeScriptCallbackProbe.handlerName)
        }
        let host = WebBridgeTestWebViewHost(webView)
        defer {
            bridge.detach()
            Task {
                await slow.releaseAllForTeardown()
                await other.releaseAllForTeardown()
            }
            webView.configuration.userContentController.removeScriptMessageHandler(forName: WebBridgeScriptCallbackProbe.handlerName)
            tearDownWebBridgeTestWebView(webView)
            host.tearDown()
        }

        #expect(bridge.attach(webView: webView, allowedOriginRules: ["https://login.example.test"]) == nil)
        try await loadWebBridgeTestHTML(
            webBridgeRuntimeHTML,
            baseURL: URL(string: "https://login.example.test/start")!,
            in: webView
        )

        try await invokeWebBridgePlugin(pluginID: "SLOW", action: "first", in: webView)
        #expect(try await slow.waitForStartCount(1) == 1)

        try await invokeWebBridgePlugin(pluginID: "SLOW", action: "second", in: webView)

        try await invokeWebBridgePlugin(pluginID: "OTHER", action: "parallel", in: webView)
        #expect(try await other.waitForStartCount(1) == 1)
        #expect(await slow.startCount() == 1)

        await slow.releaseNext()
        #expect(try await slow.waitForStartCount(2) == 2)
        await slow.releaseNext()
        await other.releaseNext()
        _ = try await callbacks.waitForMessageCount(3)

        let sequence = events.get()
        let firstFinish = try #require(sequence.firstIndex(of: "SLOW:finish:first"))
        let secondStart = try #require(sequence.firstIndex(of: "SLOW:start:second"))
        let otherStart = try #require(sequence.firstIndex(of: "OTHER:start:parallel"))
        #expect(firstFinish < secondStart)
        #expect(otherStart < firstFinish)
        #expect(await slow.invocationActionsSnapshot() == ["first", "second"])
        #expect(await other.invocationActionsSnapshot() == ["parallel"])
    }

    private func makeBridge(
        plugins: [any WebBridgePlugin],
        logger: OwnIDLogRouter? = nil,
        uiContextProvider: WebBridgeUIContextProviderImpl = WebBridgeUIContextProviderImpl(),
        appConfigProvider: any AppConfigProvider = SilentAppConfigProvider()
    ) -> WebBridgeImpl {
        WebBridgeImpl(
            plugins: WebBridgePluginRegistryImpl(initialPlugins: plugins),
            appConfigProvider: appConfigProvider,
            coder: JSONCoderImpl(),
            uiContextProvider: uiContextProvider,
            logger: logger
        )
    }

    private static func appConfig(allowedOrigins: Set<String>) -> AppConfig {
        AppConfig(
            loginIdConfig: AppConfig.default.loginIdConfig,
            displayName: nil,
            webView: AppConfig.WebViewConfig(
                baseUrl: nil,
                html: nil,
                allowedOrigins: allowedOrigins
            ),
            ui: nil,
            logLevel: .warning
        )
    }

    private func loadAndInvokeEcho(in webView: WKWebView, origin: String) async throws {
        try await loadWebBridgeTestHTML(
            webBridgeRuntimeHTML,
            baseURL: try #require(URL(string: "\(origin)/start")),
            in: webView
        )
        try await invokeWebBridgePlugin(pluginID: "ECHO", action: "get", in: webView)
    }
}

// Covers: WB-BRIDGE-120
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
    let result = try #require(try await evaluateWebBridgeTestJavaScript("String(window.OwnID.callbackCount);", in: webView))
    return try #require(Int(result), "Expected a numeric WebBridge callback count")
}

@MainActor
private final class WebBridgeTestWeakReference {
    weak var bridge: WebBridgeImpl?

    init(_ bridge: WebBridgeImpl?) {
        self.bridge = bridge
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
    private let messages = AsyncSignalRecorder<RuntimeWebBridgeReceivedMessage>()
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

    func waitForMessage() async throws -> RuntimeWebBridgeReceivedMessage {
        try await messages.waitForFirst("WebBridge plugin message") { _ in true }
    }

    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        lock.withLock { count += 1 }
        messages.append(
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
    private let events: FlowLocked<[String]>
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private let starts = AsyncSignalRecorder<Int>()
    private var isReleasedForTeardown = false
    private var cancelCountValue = 0
    private let cancellations = AsyncSignalRecorder<Int>()

    init(
        id: String,
        actions: [String] = ["first", "second", "parallel", "get"],
        events: FlowLocked<[String]> = FlowLocked([])
    ) {
        self.key = WebBridgePluginKey(id: id)
        self.actions = actions
        self.events = events
    }

    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        invocationActions.append(message.payload.action)
        events.mutate { $0.append("\(key.id):start:\(message.payload.action)") }
        defer { events.mutate { $0.append("\(key.id):finish:\(message.payload.action)") } }
        starts.append(invocationActions.count)

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isReleasedForTeardown {
                    continuation.resume()
                } else {
                    releaseContinuations.append(continuation)
                }
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

    func releaseAllForTeardown() {
        isReleasedForTeardown = true
        let pending = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    func waitForStartCount(_ count: Int) async throws -> Int {
        try await starts.waitForFirst("WebBridge \(key.id) plugin start count \(count)") { $0 >= count }
    }

    func startCount() -> Int {
        invocationActions.count
    }

    func invocationActionsSnapshot() -> [String] {
        invocationActions
    }

    func waitForCancelCount(_ count: Int) async throws -> Int {
        try await cancellations.waitForFirst("WebBridge \(key.id) plugin cancellation count \(count)") { $0 >= count }
    }

    private func recordCancellation() {
        cancelCountValue += 1
        cancellations.append(cancelCountValue)
    }
}

private final class SilentAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    var currentConfig: AppConfig? { .default }

    func getOrFetchConfig() async throws -> AppConfig {
        .default
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private final class ControlledWebBridgeAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    private let state = ControlledWebBridgeAppConfigState()
    private let snapshot = Locked<AppConfig?>(nil)

    var currentConfig: AppConfig? { snapshot.get() }

    func getOrFetchConfig() async throws -> AppConfig {
        .default
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream(
            unfolding: { [state] in await state.next() },
            onCancel: { [state] in Task { await state.finish() } }
        )
    }

    func yieldAndWaitForObservation(_ config: AppConfig) async {
        snapshot.set(config)
        let nextRequestAfterObservation = await state.enqueue(config)
        await state.waitForRequest(nextRequestAfterObservation)
    }
}

private actor ControlledWebBridgeAppConfigState {
    private var queued: [AppConfig] = []
    private var nextContinuation: CheckedContinuation<AppConfig?, Never>?
    private var submittedCount = 0
    private var requestCount = 0
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var isFinished = false

    func enqueue(_ config: AppConfig) -> Int {
        guard !isFinished else { return requestCount }
        submittedCount += 1
        if let continuation = nextContinuation {
            nextContinuation = nil
            continuation.resume(returning: config)
        } else {
            queued.append(config)
        }
        // The observation loop requests its next element only after storing this
        // configuration in the bridge cache.
        return submittedCount + 1
    }

    func next() async -> AppConfig? {
        markRequest()
        guard !isFinished else { return nil }
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            nextContinuation = continuation
        }
    }

    func waitForRequest(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        queued.removeAll()
        nextContinuation?.resume(returning: nil)
        nextContinuation = nil
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.1.resume() }
    }

    private func markRequest() {
        requestCount += 1
        let ready = requestWaiters.filter { $0.0 <= requestCount }
        requestWaiters.removeAll { $0.0 <= requestCount }
        ready.forEach { $0.1.resume() }
    }
}

private enum RuntimeWebBridgeFactoryError: Error {
    case expected
}
