import Foundation
import SwiftUI
import Testing
import UIKit
import WebKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: WB-BRIDGE-130, WB-BRIDGE-140, WB-BRIDGE-170, WB-BRIDGE-180, WB-BRIDGE-190, WB-BRIDGE-200, WB-BRIDGE-310, WB-BRIDGE-320
@MainActor
@Suite(.serialized)
struct WebBridgeWebViewRuntimeTests {

    @Test func `Coordinator blocks unsafe navigation schemes in both delegate paths and keeps OwnID callbacks internal`() async throws {
        let openedURLs = FlowLocked<[URL]>([])
        var coordinator: WebBridgeWebViewCoordinator? = WebBridgeWebViewCoordinator(
            logger: nil,
            onWebViewDetach: {},
            openURL: { url in openedURLs.mutate { $0.append(url) } }
        )
        let lifetime = WebBridgeCoordinatorWeakReference(coordinator)
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator?.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        for url in Self.blockedNavigationURLs {
            let action = TestWebBridgeNavigationAction(url: url)
            var policy: WKNavigationActionPolicy?

            coordinator?.webView(webView, decidePolicyFor: action) { policy = $0 }
            let createdWebView = coordinator?.webView(
                webView,
                createWebViewWith: WKWebViewConfiguration(),
                for: action,
                windowFeatures: WKWindowFeatures()
            )

            #expect(policy == .cancel)
            #expect(createdWebView == nil)
        }

        let exceptionSink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        coordinator?.activeUIState = makeUIState(
            onTerminalError: { error, message in
                exceptionSink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        var ownIDPolicy: WKNavigationActionPolicy?
        coordinator?.webView(
            webView,
            decidePolicyFor: TestWebBridgeNavigationAction(url: URL(string: "ownid://on-js-exception?ex=callback%20kept")!)
        ) { ownIDPolicy = $0 }

        #expect(ownIDPolicy == .cancel)
        let exception = try await exceptionSink.waitForFirst("wait for ownid decide-policy callback") { _ in true }
        #expect(exception.errorDescription == nil)
        #expect(exception.message == "callback kept")

        let loadErrorSink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        coordinator?.activeUIState = makeUIState(
            onTerminalError: { error, message in
                loadErrorSink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        let ownIDCreatedWebView = coordinator?.webView(
            webView,
            createWebViewWith: WKWebViewConfiguration(),
            for: TestWebBridgeNavigationAction(url: URL(string: "ownid://on-js-load-error")!),
            windowFeatures: WKWindowFeatures()
        )

        #expect(ownIDCreatedWebView == nil)
        let loadError = try await loadErrorSink.waitForFirst("wait for ownid create-webview callback") { _ in true }
        #expect(loadError.errorDescription == nil)
        #expect(loadError.message == "JS load error: ownid://on-js-load-error")
        coordinator?.detach()
        coordinator = nil
        try await withTestTimeout("WebBridge coordinator navigation handler release") { @MainActor in
            while lifetime.coordinator != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        #expect(openedURLs.get().isEmpty)
    }

    @Test func `Coordinator maps JavaScript callback URLs to terminal errors`() async throws {
        let jsExceptionSink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                jsExceptionSink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )

        coordinator.handleOwnIdURL(URL(string: "ownid://on-js-exception?ex=script%20failed")!)

        let jsException = try await jsExceptionSink.waitForFirst("wait for JS exception callback") { _ in true }
        #expect(jsException.errorDescription == nil)
        #expect(jsException.message == "script failed")

        let loadErrorSink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                loadErrorSink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )

        coordinator.handleOwnIdURL(URL(string: "ownid://on-js-load-error")!)

        let loadError = try await loadErrorSink.waitForFirst("wait for JS load-error callback") { _ in true }
        #expect(loadError.errorDescription == nil)
        #expect(loadError.message == "JS load error: ownid://on-js-load-error")
    }

    @Test func `Coordinator maps navigation failures to terminal errors`() async throws {
        let sink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                sink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator.detach()
            tearDownWebBridgeTestWebView(webView)
        }
        let error = WebBridgeViewError(description: "navigation failed")

        coordinator.webView(webView, didFail: nil, withError: error)

        let event = try await sink.waitForFirst("wait for navigation failure callback") { _ in true }
        #expect(event.errorDescription == "navigation failed")
        #expect(event.message == nil)
    }

    @Test func `Coordinator maps provisional navigation failures to terminal errors`() async throws {
        let sink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                sink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator.detach()
            tearDownWebBridgeTestWebView(webView)
        }
        let error = WebBridgeViewError(description: "provisional navigation failed")

        coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: error)

        let event = try await sink.waitForFirst("wait for provisional navigation failure callback") { _ in true }
        #expect(event.errorDescription == "provisional navigation failed")
        #expect(event.message == nil)
        #expect(coordinator.initialDocumentBaseURL == nil)
    }

    @Test func `Coordinator maps render-process termination and resets load state`() async throws {
        let sink = AsyncSignalRecorder<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.isBridgeInjected = true
        coordinator.hasLoaded = true
        coordinator.initialDocumentBaseURL = URL(string: "https://login.example.com")
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                sink.append(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        coordinator.webViewWebContentProcessDidTerminate(webView)

        #expect(!coordinator.isBridgeInjected)
        #expect(!coordinator.hasLoaded)
        let event = try await sink.waitForFirst("wait for render-process callback") { _ in true }
        #expect(event.errorDescription == nil)
        #expect(event.message == "WebView render process terminated")
    }

    @Test func `Coordinator retries bridge injection after navigation finish when initial injection did not run`() async throws {
        let injectCount = FlowLocked(0)
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onInject: { _ in injectCount.mutate { $0 += 1 } }
        )
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator.detach()
            tearDownWebBridgeTestWebView(webView)
        }

        coordinator.webView(webView, didFinish: nil)

        #expect(coordinator.isBridgeInjected)
        #expect(injectCount.get() == 1)
        #expect(coordinator.initialDocumentBaseURL == nil)
    }

    @Test func `Coordinator detach clears load state and invokes detach callback`() async throws {
        let detachSink = AsyncSignalRecorder<Bool>()
        let coordinator = WebBridgeWebViewCoordinator(
            logger: nil,
            onWebViewDetach: {
                detachSink.append(true)
            }
        )
        coordinator.activeUIState = makeUIState()
        coordinator.isBridgeInjected = true
        coordinator.hasLoaded = true
        coordinator.initialDocumentBaseURL = URL(string: "https://login.example.com")

        coordinator.detach()

        #expect(coordinator.activeUIState == nil)
        #expect(!coordinator.isBridgeInjected)
        #expect(!coordinator.hasLoaded)
        #expect(coordinator.initialDocumentBaseURL == nil)
        let didDetach = try await detachSink.waitForFirst("wait for WebBridge detach callback") { _ in true }
        #expect(didDetach)
    }

    @Test func `Coordinator keeps only initial same-origin document load inside WebView`() {
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.initialDocumentBaseURL = URL(string: "https://login.example.com:8443/start")

        #expect(
            coordinator.allowsNavigationInWebView(
                URL(string: "https://login.example.com:8443/next")!,
                navigationType: .other,
                targetFrameIsNil: false
            )
        )
        #expect(
            coordinator.allowsNavigationInWebView(
                URL(string: "https://login.example.com:8443/reload")!,
                navigationType: .reload,
                targetFrameIsNil: false
            )
        )
        #expect(
            !coordinator.allowsNavigationInWebView(
                URL(string: "https://login.example.com/next")!,
                navigationType: .other,
                targetFrameIsNil: false
            )
        )
        #expect(
            !coordinator.allowsNavigationInWebView(
                URL(string: "https://other.example.com:8443/next")!,
                navigationType: .other,
                targetFrameIsNil: false
            )
        )
        #expect(
            !coordinator.allowsNavigationInWebView(
                URL(string: "https://login.example.com:8443/next")!,
                navigationType: .linkActivated,
                targetFrameIsNil: false
            )
        )
        #expect(
            !coordinator.allowsNavigationInWebView(
                URL(string: "https://login.example.com:8443/next")!,
                navigationType: .other,
                targetFrameIsNil: true
            )
        )
        #expect(
            coordinator.allowsNavigationInWebView(
                URL(string: "about:blank")!,
                navigationType: .other,
                targetFrameIsNil: true
            )
        )

        coordinator.initialDocumentBaseURL = nil
        #expect(
            !coordinator.allowsNavigationInWebView(
                URL(string: "https://login.example.com:8443/reload")!,
                navigationType: .reload,
                targetFrameIsNil: false
            )
        )
    }

    @Test func `Hosted WebView applies construction and active state properties without reinjecting on update`() async throws {
        let injectCount = FlowLocked(0)
        let model = WebBridgeWebViewHarnessModel()
        let uiState = makeUIState(
            baseUrl: "https://login.example.test/start",
            html: "<html><body>flow</body></html>",
            userAgent: "OwnIDHosted/1.0",
            webViewIsInspectable: true,
            backgroundColor: .systemGreen,
            onInject: { _ in injectCount.mutate { $0 += 1 } }
        )
        let host = UIHostingController(
            rootView: HostedWebBridgeWebViewHarness(
                model: model,
                state: .active(uiState: uiState),
                configuration: WebBridgeWebViewConfiguration(limitsNavigationsToAppBoundDomains: true)
            )
        )
        let window = makeWebBridgeHostWindow(rootViewController: host)
        defer { tearDownWebBridgeHostWindow(window) }

        let webView = try requireHostedWebBridgeWKWebView(in: host.view)
        defer { tearDownWebBridgeTestWebView(webView) }
        let coordinator = try #require(webView.navigationDelegate as? WebBridgeWebViewCoordinator)

        #expect(webView.uiDelegate === coordinator)
        if #available(iOS 14.0, *) {
            #expect(webView.configuration.limitsNavigationsToAppBoundDomains)
        }
        if #available(iOS 16.4, *) {
            #expect(webView.isInspectable)
        }
        #expect(webView.customUserAgent == "OwnIDHosted/1.0")
        #expect(webView.backgroundColor == .systemGreen)
        #expect(webView.scrollView.backgroundColor == .systemGreen)
        #expect(coordinator.activeUIState != nil)
        #expect(coordinator.isBridgeInjected)
        #expect(coordinator.hasLoaded)
        #expect(coordinator.initialDocumentBaseURL == URL(string: "https://login.example.test/start"))
        #expect(injectCount.get() == 1)

        model.bump()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        _ = try requireHostedWebBridgeWKWebView(in: host.view)

        #expect(webView.navigationDelegate === coordinator)
        #expect(coordinator.isBridgeInjected)
        #expect(coordinator.hasLoaded)
        #expect(injectCount.get() == 1)
    }

    private static let blockedNavigationURLs: [URL] = [
        URL(string: "javascript:alert(1)")!,
        URL(string: "data:text/html;base64,PGh0bWw+")!,
        URL(string: "file:///private/var/tmp/ownid.html")!,
        URL(string: "content://com.example.provider/ownid")!,
        URL(string: "intent://login.example.test/#Intent;scheme=https;end")!,
    ]
}

@MainActor
@Suite(.serialized)
struct WebBridgeOperationUIBoundaryRuntimeTests {

    @Test func `Operation reports and logs AppConfig startup failure before starting UI`() async throws {
        let ui = CapturingWebBridgeUI()
        let logSink = LogCapture()
        let taskScope = TaskScope(shutdownToken: ShutdownToken())
        let operation = WebBridgeOperationImpl(
            operationType: .webBridge,
            operationRegistry: OperationRegistryImpl(logger: nil),
            configuration: try OwnIDConfigurationImpl(appID: "webbridgeappconfigfailure"),
            appConfigProvider: ThrowingWebBridgeAppConfigProvider(),
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            webBridge: CapturingWebBridge(),
            taskScope: taskScope,
            logger: webBridgeTestLogRouter(sink: logSink)
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            taskScope.shutdown()
            ui.releaseCapturedStart()
        }

        operation.start()

        let result = try await waitForCompletedWebBridgeState(operation.controller)
        guard case .failure(.unexpected(let errorCode, let message, let underlyingError)) = result else {
            Issue.record("Expected an unexpected AppConfig startup failure, got \(result)")
            return
        }
        #expect(errorCode == .unknown)
        #expect(message.contains("Failed to load AppConfig before starting WebBridge"))
        #expect(underlyingError?.localizedDescription == "app config unavailable")
        #expect(ui.startCount == 0)
        #expect(
            logSink.entries.contains {
                $0.level == .warn
                    && $0.message.contains("Failed to load AppConfig before starting WebBridge")
                    && $0.causeDescription == "app config unavailable"
            }
        )
    }

    @Test func `Operation applies explicit WebView options at UI startup boundary`() async throws {
        let appConfig = AppConfig(
            loginIdConfig: AppConfig.default.loginIdConfig,
            displayName: nil,
            webView: AppConfig.WebViewConfig(
                baseUrl: "https://server.example.com/start",
                html: "<html>server</html>",
                allowedOrigins: nil
            ),
            ui: nil,
            logLevel: .warning
        )
        let ui = CapturingWebBridgeUI()
        let bridge = CapturingWebBridge()
        let localInfo = WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: false)
        let operation = try makeOperation(appConfig: appConfig, localInfo: localInfo, ui: ui, bridge: bridge)
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }
        let resolvedBaseUrl = AsyncSignalRecorder<String>()
        let options = WebBridgeOperationOptions(
            baseUrl: "https://login.example.com:8443/path?flow=1",
            html: "<html>custom</html>",
            userAgent: "OwnIDCustom/2.0",
            webViewIsInspectable: true,
            backgroundColor: .systemTeal,
            limitsNavigationsToAppBoundDomains: true
        )

        let genericController = operation.start(
            params: WebBridgeOperationParams(
                options: options,
                onBaseUrlResolved: { resolvedBaseUrl.append($0) }
            )
        )
        let controller = operation.controller
        #expect(genericController.operationID == controller.operationID)

        let start = try await ui.waitForStart("wait for WebBridge UI start")
        let activeState = try await waitForActiveState(controller)
        let uiState = try #require(activeState)

        #expect(
            try await resolvedBaseUrl.waitForFirst("WebBridge resolved base URL") { _ in true }
                == "https://login.example.com:8443/path?flow=1"
        )
        #expect(start.webViewConfiguration.limitsNavigationsToAppBoundDomains)
        #expect(uiState.baseUrl == "https://login.example.com:8443/path?flow=1")
        #expect(uiState.html == "<html>custom</html>")
        #expect(uiState.userAgent == "OwnIDCustom/2.0")
        #expect(uiState.webViewIsInspectable == true)
        #expect(uiState.backgroundColor == .systemTeal)

        let webView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(webView) }
        try uiState.doWebViewBridgeInject(webView)

        let attachment = try #require(bridge.attachments.get().first)
        #expect(attachment.webViewIdentifier == ObjectIdentifier(webView))
        #expect(attachment.allowedOriginRules == ["https://login.example.com:8443"])
        controller.abort(reason: .userClose(details: "WebBridge test finished"))
        _ = try await waitForCompletedWebBridgeState(controller)
    }

    @Test func `Operation typed WebBridge start exposes the UI controller directly`() async throws {
        let ui = CapturingWebBridgeUI()
        let bridge = CapturingWebBridge()
        let localInfo = WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: false)
        let operation = try makeOperation(appConfig: AppConfig.default, localInfo: localInfo, ui: ui, bridge: bridge)
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        let controller = operation.startWebBridge(params: WebBridgeOperationParams())
        let start = try await ui.waitForStart("wait for typed WebBridge UI start")

        #expect(controller.operationID == operation.operationID)
        #expect(start.controller.operationID == controller.operationID)
        _ = try #require(await waitForActiveState(operation.controller))
        controller.abort(reason: .userClose(details: "WebBridge test finished"))
        _ = try await waitForCompletedWebBridgeState(operation.controller)
    }

    @Test func `Operation falls back to server content and local runtime options`() async throws {
        let appConfig = AppConfig(
            loginIdConfig: AppConfig.default.loginIdConfig,
            displayName: nil,
            webView: AppConfig.WebViewConfig(
                baseUrl: "https://server.example.com/start",
                html: "<html>server</html>",
                allowedOrigins: nil
            ),
            ui: nil,
            logLevel: .warning
        )
        let ui = CapturingWebBridgeUI()
        let operation = try makeOperation(
            appConfig: appConfig,
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            bridge: CapturingWebBridge()
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        operation.start()
        let controller = operation.controller

        let start = try await ui.waitForStart("wait for fallback WebBridge UI start")
        let uiState = try #require(try await waitForActiveState(controller))

        #expect(!start.webViewConfiguration.limitsNavigationsToAppBoundDomains)
        #expect(uiState.baseUrl == "https://server.example.com/start")
        #expect(uiState.html == "<html>server</html>")
        #expect(uiState.userAgent == "OwnIDLocal/1.0")
        #expect(uiState.webViewIsInspectable == true)
        #expect(uiState.backgroundColor == nil)
        controller.abort(reason: .userClose(details: "WebBridge test finished"))
        _ = try await waitForCompletedWebBridgeState(controller)
    }

    @Test func `Operation settles as UI failure when bridge attachment fails`() async throws {
        let appConfig = AppConfig(
            loginIdConfig: AppConfig.default.loginIdConfig,
            displayName: nil,
            webView: AppConfig.WebViewConfig(
                baseUrl: "https://server.example.com/start",
                html: "<html>server</html>",
                allowedOrigins: nil
            ),
            ui: nil,
            logLevel: .warning
        )
        let ui = CapturingWebBridgeUI()
        let bridge = CapturingWebBridge(attachError: .general("attach refused"))
        let operation = try makeOperation(
            appConfig: appConfig,
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            bridge: bridge
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        operation.start()
        let controller = operation.controller
        _ = try await ui.waitForStart("wait for attach-failure UI start")
        let uiState = try #require(try await waitForActiveState(controller))

        let webView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(webView) }
        try uiState.doWebViewBridgeInject(webView)

        let failure = try requireWebBridgeUIFailure(try await waitForCompletedWebBridgeState(controller))
        #expect(failure.message.contains("WebBridge injection failed"))
        #expect(failure.message.contains("attach refused"))
        #expect(bridge.attachments.get().count == 1)
    }

    @Test func `Delayed UI start failure settles once without detach reclassification`() async throws {
        let ui = CapturingWebBridgeUI()
        let bridge = CapturingWebBridge()
        let operation = try makeOperation(
            appConfig: Self.webBridgeAppConfig(),
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            bridge: bridge
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        operation.start()
        let start = try await ui.waitForStart("wait for delayed WebBridge UI failure callback")
        let uiState = try #require(try await waitForActiveState(operation.controller))
        let expectedFailure = WebBridgeOperationFailure.UI(
            errorCode: .unknown,
            message: "presentation acknowledgement timed out"
        )

        start.onStartError(expectedFailure)

        let failure = try requireWebBridgeUIFailure(try await waitForCompletedWebBridgeState(operation.controller))
        #expect(failure.errorCode == expectedFailure.errorCode)
        #expect(failure.message == expectedFailure.message)

        start.onDetach()
        uiState.onWebViewTerminalError(nil, "late terminal error")
        operation.controller.abort(reason: .userClose(details: "late abort"))

        let afterLateSignals = try requireWebBridgeUIFailure(
            try await waitForCompletedWebBridgeState(operation.controller)
        )
        #expect(afterLateSignals.message == expectedFailure.message)
        #expect(bridge.detachCount.get() == 1)
    }

    @Test func `Operation maps active WebView terminal failure to UI failure once`() async throws {
        let ui = CapturingWebBridgeUI()
        let operation = try makeOperation(
            appConfig: Self.webBridgeAppConfig(),
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            bridge: CapturingWebBridge()
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        operation.start()
        let uiState = try #require(try await waitForActiveState(operation.controller))

        uiState.onWebViewTerminalError(WebBridgeViewError(description: "web content failed"), nil)

        let failure = try requireWebBridgeUIFailure(try await waitForCompletedWebBridgeState(operation.controller))
        #expect(failure.message.contains("web content failed"))

        uiState.onWebViewTerminalError(nil, "late terminal error")
        let afterLateFailure = try requireWebBridgeUIFailure(try await waitForCompletedWebBridgeState(operation.controller))
        #expect(afterLateFailure.message == failure.message)
    }

    @Test func `Operation detach cancels active WebBridge and detaches bridge once`() async throws {
        let ui = CapturingWebBridgeUI()
        let bridge = CapturingWebBridge()
        let operation = try makeOperation(
            appConfig: Self.webBridgeAppConfig(),
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            bridge: bridge
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        operation.start()
        let start = try await ui.waitForStart("wait for detach WebBridge UI start")
        _ = try #require(try await waitForActiveState(operation.controller))

        start.onDetach()

        let reason = try requireOperationCancellation(try await waitForCompletedWebBridgeState(operation.controller))
        #expect(reason.description.contains("Elite UI detached"))
        #expect(bridge.detachCount.get() == 1)
    }

    @Test func `Operation terminal wrapper success settles once and suppresses detach cancellation`() async throws {
        let plugin = WebBridgeElitePlugin(
            sessionCreate: nil,
            passwordAuthenticate: nil,
            loginIDValidator: WebBridgePluginMatrixLoginIDValidator(),
            coder: JSONCoderImpl()
        )
        let ui = CapturingWebBridgeUI()
        let bridge = CapturingWebBridge(plugins: [plugin])
        let operation = try makeOperation(
            appConfig: Self.webBridgeAppConfig(),
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: ui,
            bridge: bridge
        )
        defer {
            operation.controller.abort(reason: .userClose(details: "WebBridge test teardown"))
            ui.releaseCapturedStart()
        }

        operation.start(
            params: WebBridgeOperationParams(
                eventWrappers: [WebBridgePluginMatrixEventWrapper(action: "onFinish")]
            )
        )
        let start = try await ui.waitForStart("wait for terminal WebBridge UI start")
        _ = try #require(try await waitForActiveState(operation.controller))

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "FLOW",
            action: "onFinish",
            params: #"{"loginId":"person@example.test"}"#
        )
        #expect(result.error == nil)

        try requireOperationSuccess(try await waitForCompletedWebBridgeState(operation.controller))
        start.onDetach()
        try requireOperationSuccess(try await waitForCompletedWebBridgeState(operation.controller))
        #expect(bridge.detachCount.get() == 1)
    }

    private static func webBridgeAppConfig() -> AppConfig {
        AppConfig(
            loginIdConfig: AppConfig.default.loginIdConfig,
            displayName: nil,
            webView: AppConfig.WebViewConfig(
                baseUrl: "https://server.example.com/start",
                html: "<html>server</html>",
                allowedOrigins: nil
            ),
            ui: nil,
            logLevel: .warning
        )
    }
}

@MainActor
@Suite(.serialized)
struct WebBridgePresenterRuntimeTests {

    @Test func `Presenter reports startup failure when no host is available`() async throws {
        WebBridgePresenterImpl.__testResetLaunchFlag()
        let contextProvider = FixedWebBridgeUIContextProvider(host: nil)
        let presenter = WebBridgePresenterImpl(uiContextProvider: contextProvider, logger: nil)
        let controller = makePresenterController(id: "startup-failure")
        let failureSink = AsyncSignalRecorder<WebBridgeOperationFailure.UI>()
        let detachCount = FlowLocked(0)
        defer {
            presenter.dismiss()
            WebBridgePresenterImpl.__testResetLaunchFlag()
        }

        let immediateFailure = presenter.present(
            controller: controller,
            onWebViewDetach: { detachCount.mutate { $0 += 1 } },
            onFailure: { failureSink.append($0) }
        )

        #expect(immediateFailure?.message.contains("UI context unavailable") == true)
        #expect(failureSink.entries.isEmpty)
        #expect(detachCount.get() == 0)
    }

    @Test func `Presenter enforces one process-wide launch across presenter instances until teardown`() async throws {
        WebBridgePresenterImpl.__testResetLaunchFlag()
        let firstHost = DeferredWebBridgePresentationHostViewController()
        let secondHost = DeferredWebBridgePresentationHostViewController()
        let firstWindow = makeWebBridgeHostWindow(rootViewController: firstHost)
        let secondWindow = makeWebBridgeHostWindow(rootViewController: secondHost)
        let firstPresenter = WebBridgePresenterImpl(
            uiContextProvider: FixedWebBridgeUIContextProvider(host: firstHost),
            logger: nil
        )
        let secondPresenter = WebBridgePresenterImpl(
            uiContextProvider: FixedWebBridgeUIContextProvider(host: secondHost),
            logger: nil
        )
        let firstController = makePresenterController(id: "first")
        let secondController = makePresenterController(id: "second")
        defer {
            firstPresenter.dismiss()
            secondPresenter.dismiss()
            tearDownWebBridgeHostWindow(firstWindow)
            tearDownWebBridgeHostWindow(secondWindow)
            WebBridgePresenterImpl.__testResetLaunchFlag()
        }

        let firstFailure = firstPresenter.present(controller: firstController, onWebViewDetach: {}, onFailure: { _ in })
        let duplicateFailure = secondPresenter.present(controller: secondController, onWebViewDetach: {}, onFailure: { _ in })

        #expect(firstFailure == nil)
        #expect(duplicateFailure?.message.contains("Launch already in progress") == true)

        firstHost.completeLatestPresentation()
        firstPresenter.dismiss()
        firstHost.detachPresentedController()

        try await waitUntilPresenterAcceptsLaunch(
            secondPresenter,
            controller: secondController,
            onAccepted: {
                secondHost.completeLatestPresentation()
                secondPresenter.dismiss()
                secondHost.detachPresentedController()
            }
        )
    }

    @Test func `Presenter watchdog fails once and stale completion cannot release a replacement launch`() async throws {
        WebBridgePresenterImpl.__testResetLaunchFlag()
        let expiredHost = DeferredWebBridgePresentationHostViewController()
        let replacementHost = DeferredWebBridgePresentationHostViewController()
        let expiredWindow = makeWebBridgeHostWindow(rootViewController: expiredHost)
        let replacementWindow = makeWebBridgeHostWindow(rootViewController: replacementHost)
        let expiredPresenter = WebBridgePresenterImpl(
            uiContextProvider: FixedWebBridgeUIContextProvider(host: expiredHost),
            logger: nil
        )
        let replacementPresenter = WebBridgePresenterImpl(
            uiContextProvider: FixedWebBridgeUIContextProvider(host: replacementHost),
            logger: nil
        )
        let failures = AsyncSignalRecorder<WebBridgeOperationFailure.UI>()
        let detachCount = FlowLocked(0)
        defer {
            expiredPresenter.dismiss()
            replacementPresenter.dismiss()
            expiredHost.detachPresentedController()
            replacementHost.detachPresentedController()
            tearDownWebBridgeHostWindow(expiredWindow)
            tearDownWebBridgeHostWindow(replacementWindow)
            WebBridgePresenterImpl.__testResetLaunchFlag()
        }

        #expect(
            expiredPresenter.present(
                controller: makePresenterController(id: "watchdog-expired"),
                onWebViewDetach: { detachCount.mutate { $0 += 1 } },
                onFailure: { failures.append($0) }
            ) == nil
        )

        let failure = try await failures.waitForFirst("WebBridge presentation watchdog", seconds: 10) { _ in true }
        #expect(failure.errorCode == .unknown)
        #expect(failure.message == "Failed to present WebBridge UI: Presentation completion timed out")
        #expect(failures.entries.count == 1)
        #expect(detachCount.get() == 0)

        let replacementController = makePresenterController(id: "watchdog-replacement")
        try await waitUntilPresenterAcceptsLaunch(
            replacementPresenter,
            controller: replacementController,
            onAccepted: {}
        )

        expiredHost.completeLatestPresentation()
        expiredPresenter.dismiss()
        let staleReleaseProbe = expiredPresenter.present(
            controller: makePresenterController(id: "stale-release-probe"),
            onWebViewDetach: {},
            onFailure: { _ in }
        )

        #expect(staleReleaseProbe?.message.contains("Launch already in progress") == true)
        #expect(failures.entries.count == 1)
        #expect(detachCount.get() == 0)

        replacementHost.completeLatestPresentation()
        replacementPresenter.dismiss()
        replacementHost.detachPresentedController()
    }

    @Test func `Presenter rejects incomplete and unavailable presentation contexts immediately`() {
        WebBridgePresenterImpl.__testResetLaunchFlag()
        let host = UIViewController()
        let window = makeWebBridgeHostWindow(rootViewController: host)
        defer {
            tearDownWebBridgeHostWindow(window)
            WebBridgePresenterImpl.__testResetLaunchFlag()
        }

        let windowOnlyPresenter = WebBridgePresenterImpl(
            uiContextProvider: WebBridgeTestUIContextProvider(result: .windowOnly(window)),
            logger: nil
        )
        let windowOnlyFailure = windowOnlyPresenter.present(
            controller: makePresenterController(id: "window-only"),
            onWebViewDetach: {},
            onFailure: { _ in }
        )
        #expect(windowOnlyFailure?.message.contains("does not include a presentation controller") == true)

        for variant in WebBridgeUnavailableHostVariant.allCases {
            let fixture = variant.makeFixture()
            defer { fixture.close() }
            let presenter = WebBridgePresenterImpl(
                uiContextProvider: WebBridgeTestUIContextProvider(result: fixture.context),
                logger: nil
            )
            let failure = presenter.present(
                controller: makePresenterController(id: "unavailable-\(variant.testDescription)"),
                onWebViewDetach: {},
                onFailure: { _ in }
            )
            #expect(
                failure?.message.contains("Host is transitioning or off-screen") == true,
                "Expected rejection for \(variant.testDescription)"
            )
        }
    }

    @Test func `Presenter releases launch after dismiss is requested while presentation is pending`() async throws {
        WebBridgePresenterImpl.__testResetLaunchFlag()
        let host = DeferredWebBridgePresentationHostViewController()
        let window = makeWebBridgeHostWindow(rootViewController: host)
        let contextProvider = FixedWebBridgeUIContextProvider(host: host)
        let presenter = WebBridgePresenterImpl(uiContextProvider: contextProvider, logger: nil)
        let controller = makePresenterController(id: "pending-dismiss")
        let failureCount = FlowLocked(0)
        defer {
            presenter.dismiss()
            tearDownWebBridgeHostWindow(window)
            WebBridgePresenterImpl.__testResetLaunchFlag()
        }

        let immediateFailure = presenter.present(
            controller: controller,
            onWebViewDetach: {},
            onFailure: { _ in failureCount.mutate { $0 += 1 } }
        )

        #expect(immediateFailure == nil)
        #expect(host.presentationCount == 1)

        presenter.dismiss()

        let duplicateFailure = presenter.present(
            controller: makePresenterController(id: "pending-dismiss-duplicate"),
            onWebViewDetach: {},
            onFailure: { _ in }
        )
        #expect(duplicateFailure?.message.contains("Launch already in progress") == true)

        host.completeLatestPresentation()
        presenter.dismiss()
        host.detachPresentedController()

        try await waitUntilPresenterAcceptsLaunch(
            presenter,
            controller: makePresenterController(id: "pending-dismiss-after-release"),
            onAccepted: {
                host.completeLatestPresentation()
                presenter.dismiss()
                host.detachPresentedController()
            }
        )
        #expect(failureCount.get() == 0)
    }

}

@MainActor
@Suite(.serialized)
struct WebBridgeViewControllerRuntimeTests {

    @Test func `Initial presentation gives the hosted document focus`() async throws {
        let viewController = makeViewController(abortOperation: { _ in })
        let window = makeWebBridgeHostWindow(rootViewController: viewController)
        defer { tearDownWebBridgeHostWindow(window) }
        viewController.beginAppearanceTransition(true, animated: false)
        viewController.endAppearanceTransition()

        let webView = try requireHostedWebBridgeWKWebView(in: viewController.view)
        let documentHasFocus = try await evaluateWebBridgeTestJavaScript(
            "String(document.hasFocus())",
            in: webView
        )

        #expect(documentHasFocus == "true")
    }

    @Test func `Dismiss attempt without back stack cancels active UI state`() async throws {
        let cancelSink = AsyncSignalRecorder<String>()
        let aborts = FlowLocked<[Reason]>([])
        let viewController = makeViewController(
            abortOperation: { reason in aborts.mutate { $0.append(reason) } }
        )
        viewController.loadViewIfNeeded()
        viewController.activeUIState = makeUIState(
            onCancel: { reason in cancelSink.append(reason.description) }
        )
        let presentationController = UIPresentationController(
            presentedViewController: viewController,
            presenting: nil
        )

        viewController.presentationControllerDidAttemptToDismiss(presentationController)

        let cancellation = try await cancelSink.waitForFirst("wait for WebBridge cancel callback") { _ in true }
        #expect(cancellation.contains("User navigated back"))
        #expect(aborts.get().isEmpty)
    }

    @Test func `Dismiss attempt without active UI state aborts operation`() {
        let aborts = FlowLocked<[Reason]>([])
        let viewController = makeViewController(
            abortOperation: { reason in aborts.mutate { $0.append(reason) } }
        )
        viewController.loadViewIfNeeded()
        let presentationController = UIPresentationController(
            presentedViewController: viewController,
            presenting: nil
        )

        viewController.presentationControllerDidAttemptToDismiss(presentationController)

        #expect(aborts.get().count == 1)
        #expect(aborts.get().first?.description.contains("User navigated back") == true)
    }

    private func makeViewController(
        abortOperation: @escaping @MainActor (Reason) -> Void
    ) -> WebBridgeViewController {
        WebBridgeViewController(
            screen: WebBridgeScreen(
                controller: WebBridgeOperationControllerImpl(
                    operationID: OperationID(type: .webBridge, id: "webbridge-view-controller-test"),
                    onUserAborted: { _ in }
                ),
                logger: nil,
                onWebViewDetach: {},
                onActiveUIStateChanged: { _ in }
            ),
            logger: nil,
            abortOperation: abortOperation
        )
    }
}

private func makeUIState(
    baseUrl: String = "https://login.example.com",
    html: String = "<html></html>",
    userAgent: String = "OwnIDWebViewTests/1.0",
    webViewIsInspectable: Bool = false,
    backgroundColor: UIColor? = nil,
    onInject: @escaping @MainActor @Sendable (WKWebView) throws -> Void = { _ in },
    onTerminalError: @escaping @MainActor @Sendable ((any Error)?, String?) -> Void = { _, _ in },
    onCancel: @escaping @MainActor @Sendable (Reason) -> Void = { _ in }
) -> WebBridgeUIState {
    WebBridgeUIState(
        baseUrl: baseUrl,
        html: html,
        userAgent: userAgent,
        webViewIsInspectable: webViewIsInspectable,
        backgroundColor: backgroundColor,
        doWebViewBridgeInject: onInject,
        onWebViewTerminalError: onTerminalError,
        onWebViewCancel: onCancel
    )
}

@MainActor
private func makePresenterController(id: String) -> WebBridgeOperationControllerImpl {
    WebBridgeOperationControllerImpl(
        operationID: OperationID(type: .webBridge, id: "webbridge-presenter-\(id)"),
        onUserAborted: { _ in }
    )
}

@MainActor
private func makeWebBridgeHostWindow(rootViewController: UIViewController) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    rootViewController.loadViewIfNeeded()
    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()
    return window
}

@MainActor
private func tearDownWebBridgeHostWindow(_ window: UIWindow) {
    window.isHidden = true
    window.rootViewController = nil
}

@MainActor
private func requireHostedWebBridgeWKWebView(
    in rootView: UIView,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> WKWebView {
    rootView.setNeedsLayout()
    rootView.layoutIfNeeded()
    return try #require(findDescendantWKWebView(in: rootView), "Expected hosted WKWebView", sourceLocation: sourceLocation)
}

@MainActor
private func findDescendantWKWebView(in view: UIView) -> WKWebView? {
    if let webView = view as? WKWebView { return webView }
    for subview in view.subviews {
        if let webView = findDescendantWKWebView(in: subview) {
            return webView
        }
    }
    return nil
}

private final class WebBridgeWebViewHarnessModel: ObservableObject, @unchecked Sendable {
    @Published private(set) var updateToken = 0

    @MainActor
    func bump() {
        updateToken += 1
    }
}

private struct HostedWebBridgeWebViewHarness: View {
    @ObservedObject var model: WebBridgeWebViewHarnessModel

    let state: WebBridgeOperationState
    let configuration: WebBridgeWebViewConfiguration

    var body: some View {
        WebBridgeWebView(
            state: state,
            webViewConfiguration: configuration,
            logger: nil,
            onDetach: {}
        )
        .overlay(Text("\(model.updateToken)").hidden())
    }
}

private final class FixedWebBridgeUIContextProvider: UIContextProvider, @unchecked Sendable {
    weak var host: UIViewController?

    init(host: UIViewController?) {
        self.host = host
    }

    @MainActor
    func current() -> UIContextResult {
        guard let host, let window = host.viewIfLoaded?.window else {
            return .failure(
                UIContextResolutionError(
                    reason: .unavailable,
                    message: "No presentation host is available."
                )
            )
        }
        return .windowAndController(window: window, controller: host)
    }
}

private enum WebBridgeUnavailableHostVariant: CaseIterable, CustomTestStringConvertible {
    case hiddenWindow
    case transparentWindow
    case hiddenHost
    case transparentHost
    case detachedHost
    case mismatchedHost
    case transitioningHost
    case occupiedHost

    var testDescription: String {
        switch self {
        case .hiddenWindow: "hidden window"
        case .transparentWindow: "transparent window"
        case .hiddenHost: "hidden host"
        case .transparentHost: "transparent host"
        case .detachedHost: "detached host"
        case .mismatchedHost: "mismatched host/window"
        case .transitioningHost: "transitioning host"
        case .occupiedHost: "occupied host"
        }
    }

    @MainActor
    func makeFixture() -> WebBridgeUnavailableHostFixture {
        let host: UIViewController
        switch self {
        case .transitioningHost:
            host = WebBridgeTransitioningHostViewController()
        case .occupiedHost:
            let occupiedHost = WebBridgeOccupiedHostViewController()
            occupiedHost.presentedOverride = UIViewController()
            host = occupiedHost
        default:
            host = UIViewController()
        }

        let attachedWindow = makeWebBridgeHostWindow(rootViewController: host)
        let contextWindow: UIWindow
        if self == .mismatchedHost {
            contextWindow = UIWindow(frame: attachedWindow.bounds)
            contextWindow.isHidden = false
        } else {
            contextWindow = attachedWindow
        }
        if self == .hiddenWindow { contextWindow.isHidden = true }
        if self == .transparentWindow { contextWindow.alpha = 0 }
        if self == .hiddenHost { host.view.isHidden = true }
        if self == .transparentHost { host.view.alpha = 0 }
        if self == .detachedHost { host.view.removeFromSuperview() }

        return WebBridgeUnavailableHostFixture(
            context: .windowAndController(window: contextWindow, controller: host),
            windows: contextWindow === attachedWindow ? [attachedWindow] : [attachedWindow, contextWindow]
        )
    }
}

@MainActor
private struct WebBridgeUnavailableHostFixture {
    let context: UIContextResult
    let windows: [UIWindow]

    func close() {
        windows.forEach(tearDownWebBridgeHostWindow)
    }
}

private final class WebBridgeTransitioningHostViewController: UIViewController {
    override var isBeingPresented: Bool { true }
}

private final class WebBridgeOccupiedHostViewController: UIViewController {
    var presentedOverride: UIViewController?

    override var presentedViewController: UIViewController? {
        presentedOverride ?? super.presentedViewController
    }
}

@MainActor
private final class DeferredWebBridgePresentationHostViewController: UIViewController {
    private var pendingPresentation: (controller: UIViewController, completion: (() -> Void)?)?
    private var presentedController: UIViewController?
    private(set) var presentationCount = 0

    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        presentationCount += 1
        pendingPresentation = (viewControllerToPresent, completion)
    }

    func completeLatestPresentation() {
        guard let pendingPresentation else { return }
        self.pendingPresentation = nil
        let controller = pendingPresentation.controller
        presentedController = controller
        addChild(controller)
        controller.view.frame = view.bounds
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        pendingPresentation.completion?()
    }

    func detachPresentedController() {
        guard let presentedController else { return }
        presentedController.willMove(toParent: nil)
        presentedController.view.removeFromSuperview()
        presentedController.removeFromParent()
        self.presentedController = nil
    }
}

@MainActor
private func waitForActiveState(_ controller: WebBridgeOperationControllerImpl) async throws -> WebBridgeUIState? {
    try await withFlowTimeout("wait for WebBridge active state") {
        for await state in await controller.stateStream() {
            if case .active(let uiState) = state {
                return uiState
            }
        }
        return nil
    }
}

/// Observes the operation mapping result, not the later whenSettled storage delivery.
@MainActor
private func waitForCompletedWebBridgeState(
    _ controller: WebBridgeOperationControllerImpl
) async throws -> OperationResult<Void, WebBridgeOperationFailure> {
    try await withTestTimeout("WebBridge completed operation state") {
        for await state in await controller.stateStream() {
            if case .completed(let result) = state {
                return result
            }
        }
        throw FlowTestTimeout.streamEnded("WebBridge completed operation state")
    }
}

@MainActor
private func waitUntilPresenterAcceptsLaunch(
    _ presenter: WebBridgePresenterImpl,
    controller: WebBridgeOperationControllerImpl,
    onAccepted: @escaping @MainActor () -> Void
) async throws {
    try await withFlowTimeout("wait for WebBridge presenter launch release", seconds: 3) {
        while true {
            let didAcceptLaunch = await MainActor.run {
                let failure = presenter.present(controller: controller, onWebViewDetach: {}, onFailure: { _ in })
                guard failure == nil else { return false }
                onAccepted()
                return true
            }
            if didAcceptLaunch {
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

private func makeOperation(
    appConfig: AppConfig,
    localInfo: any LocalInfo,
    ui: CapturingWebBridgeUI,
    bridge: CapturingWebBridge
) throws -> WebBridgeOperationImpl {
    WebBridgeOperationImpl(
        operationType: .webBridge,
        operationRegistry: OperationRegistryImpl(logger: nil),
        configuration: try OwnIDConfigurationImpl(appID: "webbridge123"),
        appConfigProvider: StaticWebBridgeAppConfigProvider(config: appConfig),
        localInfo: localInfo,
        ui: ui,
        webBridge: bridge,
        taskScope: TaskScope(shutdownToken: ShutdownToken()),
        logger: nil
    )
}

private func requireWebBridgeUIFailure(
    _ result: OperationResult<Void, WebBridgeOperationFailure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> WebBridgeOperationFailure.UI {
    let failure = try requireOperationFailure(result, sourceLocation: sourceLocation)
    guard case .ui(let uiFailure) = failure else {
        return try #require(nil as WebBridgeOperationFailure.UI?, "Expected UI failure, got \(failure)", sourceLocation: sourceLocation)
    }
    return uiFailure
}

private struct WebBridgeTerminalErrorSnapshot: Sendable {
    let errorDescription: String?
    let message: String?

    init(error: (any Error)?, message: String?) {
        self.errorDescription = error?.localizedDescription
        self.message = message
    }
}

private final class TestWebBridgeNavigationAction: WKNavigationAction {
    private let testRequest: URLRequest
    private let testNavigationType: WKNavigationType
    private let testTargetFrame: WKFrameInfo?

    init(
        url: URL,
        navigationType: WKNavigationType = .linkActivated,
        targetFrame: WKFrameInfo? = nil
    ) {
        testRequest = URLRequest(url: url)
        testNavigationType = navigationType
        testTargetFrame = targetFrame
        super.init()
    }

    override var request: URLRequest { testRequest }
    override var navigationType: WKNavigationType { testNavigationType }
    override var targetFrame: WKFrameInfo? { testTargetFrame }
}

private struct WebBridgeViewError: LocalizedError, Sendable {
    let description: String
    var errorDescription: String? { description }
}

@MainActor
private final class WebBridgeCoordinatorWeakReference {
    weak var coordinator: WebBridgeWebViewCoordinator?

    init(_ coordinator: WebBridgeWebViewCoordinator?) {
        self.coordinator = coordinator
    }
}

@MainActor
private final class CapturingWebBridgeUI: WebBridgeUI, @unchecked Sendable {
    private var startCapture = AsyncSignalRecorder<Start>()
    private var isTornDown = false
    private(set) var startCount = 0

    func waitForStart(_ description: String) async throws -> Start {
        try await startCapture.waitForFirst(description) { _ in true }
    }

    func releaseCapturedStart() {
        isTornDown = true
        startCapture = AsyncSignalRecorder<Start>()
    }

    @MainActor
    func start(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration,
        onDetach: @MainActor @escaping () -> Void,
        onStartError: @MainActor @escaping (WebBridgeOperationFailure.UI) -> Void
    ) -> WebBridgeOperationFailure.UI? {
        guard !isTornDown else {
            return .init(errorCode: .unknown, message: "WebBridge test fixture already torn down")
        }
        startCount += 1
        startCapture.append(
            Start(
                controller: controller,
                webViewConfiguration: webViewConfiguration,
                onDetach: onDetach,
                onStartError: onStartError
            )
        )
        return nil
    }

    struct Start: Sendable {
        let controller: any WebBridgeOperationController
        let webViewConfiguration: WebBridgeWebViewConfiguration
        let onDetach: @MainActor () -> Void
        let onStartError: @MainActor (WebBridgeOperationFailure.UI) -> Void
    }
}

private final class CapturingWebBridge: WebBridge, @unchecked Sendable {
    let plugins: any WebBridgePluginRegistry
    let attachments = FlowLocked<[Attachment]>([])
    let detachCount = FlowLocked(0)
    private let attachError: WebBridgeError?

    init(plugins: [any WebBridgePlugin] = [], attachError: WebBridgeError? = nil) {
        self.plugins = WebBridgePluginRegistryImpl(initialPlugins: plugins)
        self.attachError = attachError
    }

    @MainActor
    func attach(webView: WKWebView, allowedOriginRules: Set<String>) -> WebBridgeError? {
        attachments.mutate {
            $0.append(Attachment(webViewIdentifier: ObjectIdentifier(webView), allowedOriginRules: allowedOriginRules))
        }
        return attachError
    }

    @MainActor
    func detach() {
        detachCount.mutate { $0 += 1 }
    }

    struct Attachment: Sendable {
        let webViewIdentifier: ObjectIdentifier
        let allowedOriginRules: Set<String>
    }
}

private final class StaticWebBridgeAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func getOrFetchConfig() async throws -> AppConfig {
        config
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.yield(config)
            continuation.finish()
        }
    }
}

private struct WebBridgeAppConfigTestError: LocalizedError, Sendable {
    var errorDescription: String? { "app config unavailable" }
}

private struct ThrowingWebBridgeAppConfigProvider: AppConfigProvider, Sendable {
    func getOrFetchConfig() async throws -> AppConfig {
        throw WebBridgeAppConfigTestError()
    }

    var configStream: AsyncStream<AppConfig> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private struct WebBridgeRuntimeLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [(name: "core", version: "test")]
    let bundleID = "com.ownid.webbridge.webview.tests"
    let appVersion = "1"
    let userAgent: String
    let correlationId = "webbridge-webview-tests"
    let isDebuggable: Bool
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = false
}
