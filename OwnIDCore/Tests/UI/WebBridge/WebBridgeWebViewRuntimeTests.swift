import Foundation
import SwiftUI
import Testing
import UIKit
import WebKit

@_spi(OwnIDInternal) @testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct WebBridgeWebViewRuntimeTests {

    @Test func `Coordinator maps JavaScript callback URLs to terminal errors`() async throws {
        let jsExceptionSink = CapturedFlowValue<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                jsExceptionSink.set(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )

        coordinator.handleOwnIdURL(URL(string: "ownid://on-js-exception?ex=script%20failed")!)

        let jsException = try await withFlowTimeout("wait for JS exception callback") {
            await jsExceptionSink.wait()
        }
        #expect(jsException.errorDescription == nil)
        #expect(jsException.message == "script failed")

        let loadErrorSink = CapturedFlowValue<WebBridgeTerminalErrorSnapshot>()
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                loadErrorSink.set(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )

        coordinator.handleOwnIdURL(URL(string: "ownid://on-js-load-error")!)

        let loadError = try await withFlowTimeout("wait for JS load-error callback") {
            await loadErrorSink.wait()
        }
        #expect(loadError.errorDescription == nil)
        #expect(loadError.message == "JS load error: ownid://on-js-load-error")
    }

    @Test func `Coordinator maps navigation failures to terminal errors`() async throws {
        let sink = CapturedFlowValue<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                sink.set(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator.detach()
            tearDownWebBridgeTestWebView(webView)
        }
        let error = WebBridgeViewError(description: "navigation failed")

        coordinator.webView(webView, didFail: nil, withError: error)

        let event = try await withFlowTimeout("wait for navigation failure callback") {
            await sink.wait()
        }
        #expect(event.errorDescription == "navigation failed")
        #expect(event.message == nil)
    }

    @Test func `Coordinator maps provisional navigation failures to terminal errors`() async throws {
        let sink = CapturedFlowValue<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                sink.set(WebBridgeTerminalErrorSnapshot(error: error, message: message))
            }
        )
        let webView = makeWebBridgeTestWebView()
        defer {
            coordinator.detach()
            tearDownWebBridgeTestWebView(webView)
        }
        let error = WebBridgeViewError(description: "provisional navigation failed")

        coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: error)

        let event = try await withFlowTimeout("wait for provisional navigation failure callback") {
            await sink.wait()
        }
        #expect(event.errorDescription == "provisional navigation failed")
        #expect(event.message == nil)
        #expect(coordinator.initialDocumentBaseURL == nil)
    }

    @Test func `Coordinator maps render-process termination and resets load state`() async throws {
        let sink = CapturedFlowValue<WebBridgeTerminalErrorSnapshot>()
        let coordinator = WebBridgeWebViewCoordinator(logger: nil, onWebViewDetach: {})
        coordinator.isBridgeInjected = true
        coordinator.hasLoaded = true
        coordinator.initialDocumentBaseURL = URL(string: "https://login.example.com")
        coordinator.activeUIState = makeUIState(
            onTerminalError: { error, message in
                sink.set(WebBridgeTerminalErrorSnapshot(error: error, message: message))
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
        let event = try await withFlowTimeout("wait for render-process callback") {
            await sink.wait()
        }
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
        let detachSink = CapturedFlowValue<Bool>()
        let coordinator = WebBridgeWebViewCoordinator(
            logger: nil,
            onWebViewDetach: {
                detachSink.set(true)
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
        let didDetach = try await withFlowTimeout("wait for WebBridge detach callback") {
            await detachSink.wait()
        }
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
}

@MainActor
@Suite(.serialized)
struct WebBridgeOperationUIBoundaryRuntimeTests {

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
        let resolvedBaseUrl = CapturedFlowValue<String>()
        let options = WebBridgeOperationOptions(
            baseUrl: "https://login.example.com:8443/path?flow=1",
            html: "<html>custom</html>",
            userAgent: "OwnIDCustom/2.0",
            webViewIsInspectable: true,
            backgroundColor: .systemTeal,
            limitsNavigationsToAppBoundDomains: true
        )

        operation.start(
            params: WebBridgeOperationParams(
                options: options,
                onBaseUrlResolved: { resolvedBaseUrl.set($0) }
            )
        )
        let controller = operation.controller

        let start = try await withFlowTimeout("wait for WebBridge UI start") {
            await ui.waitForStart()
        }
        let activeState = try await waitForActiveState(controller)
        let uiState = try #require(activeState)

        #expect(await resolvedBaseUrl.wait() == "https://login.example.com:8443/path?flow=1")
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

        operation.start()
        let controller = operation.controller

        let start = try await withFlowTimeout("wait for fallback WebBridge UI start") {
            await ui.waitForStart()
        }
        let uiState = try #require(try await waitForActiveState(controller))

        #expect(!start.webViewConfiguration.limitsNavigationsToAppBoundDomains)
        #expect(uiState.baseUrl == "https://server.example.com/start")
        #expect(uiState.html == "<html>server</html>")
        #expect(uiState.userAgent == "OwnIDLocal/1.0")
        #expect(uiState.webViewIsInspectable == true)
        #expect(uiState.backgroundColor == nil)
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

        operation.start()
        let controller = operation.controller
        _ = try await withFlowTimeout("wait for attach-failure UI start") {
            await ui.waitForStart()
        }
        let uiState = try #require(try await waitForActiveState(controller))

        let webView = makeWebBridgeTestWebView()
        defer { tearDownWebBridgeTestWebView(webView) }
        try uiState.doWebViewBridgeInject(webView)

        let failure = try requireWebBridgeUIFailure(await controller.whenSettled())
        #expect(failure.message.contains("WebBridge injection failed"))
        #expect(failure.message.contains("attach refused"))
        #expect(bridge.attachments.get().count == 1)
    }

    @Test func `Operation maps active WebView terminal failure to UI failure once`() async throws {
        let operation = try makeOperation(
            appConfig: Self.webBridgeAppConfig(),
            localInfo: WebBridgeRuntimeLocalInfo(userAgent: "OwnIDLocal/1.0", isDebuggable: true),
            ui: CapturingWebBridgeUI(),
            bridge: CapturingWebBridge()
        )

        operation.start()
        let uiState = try #require(try await waitForActiveState(operation.controller))

        uiState.onWebViewTerminalError(WebBridgeViewError(description: "web content failed"), nil)

        let failure = try requireWebBridgeUIFailure(await operation.controller.whenSettled())
        #expect(failure.message.contains("web content failed"))

        uiState.onWebViewTerminalError(nil, "late terminal error")
        let afterLateFailure = try requireWebBridgeUIFailure(await operation.controller.whenSettled())
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

        operation.start()
        let start = try await withFlowTimeout("wait for detach WebBridge UI start") {
            await ui.waitForStart()
        }
        _ = try #require(try await waitForActiveState(operation.controller))

        start.onDetach()

        let reason = try requireOperationCancellation(await operation.controller.whenSettled())
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

        operation.start(
            params: WebBridgeOperationParams(
                eventWrappers: [WebBridgePluginMatrixEventWrapper(action: "onFinish")]
            )
        )
        let start = try await withFlowTimeout("wait for terminal WebBridge UI start") {
            await ui.waitForStart()
        }
        _ = try #require(try await waitForActiveState(operation.controller))

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "FLOW",
            action: "onFinish",
            params: #"{"loginId":"person@example.test"}"#
        )
        #expect(result.error == nil)

        try requireOperationSuccess(await operation.controller.whenSettled())
        start.onDetach()
        try requireOperationSuccess(await operation.controller.whenSettled())
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
        let presenter = WebBridgePresenterImpl(uiContextProvider: FixedWebBridgeUIContextProvider(host: nil), logger: nil)
        let controller = makePresenterController(id: "startup-failure")
        let failureSink = CapturedFlowValue<WebBridgeOperationFailure.UI>()
        let detachCount = FlowLocked(0)
        defer {
            presenter.dismiss()
            WebBridgePresenterImpl.__testResetLaunchFlag()
        }

        let immediateFailure = presenter.present(
            controller: controller,
            onWebViewDetach: { detachCount.mutate { $0 += 1 } },
            onFailure: { failureSink.set($0) }
        )

        #expect(immediateFailure == nil)
        let delayedFailure = try await withFlowTimeout("wait for WebBridge presenter startup failure") {
            await failureSink.wait()
        }
        #expect(delayedFailure.message.contains("Top view controller not found"))
        #expect(detachCount.get() == 0)
    }

    @Test func `Presenter enforces one active launch until dismissed`() {
        WebBridgePresenterImpl.__testResetLaunchFlag()
        let presenter = WebBridgePresenterImpl(uiContextProvider: FixedWebBridgeUIContextProvider(host: nil), logger: nil)
        let firstController = makePresenterController(id: "first")
        let secondController = makePresenterController(id: "second")
        defer { WebBridgePresenterImpl.__testResetLaunchFlag() }

        let firstFailure = presenter.present(controller: firstController, onWebViewDetach: {}, onFailure: { _ in })
        let duplicateFailure = presenter.present(controller: secondController, onWebViewDetach: {}, onFailure: { _ in })

        #expect(firstFailure == nil)
        #expect(duplicateFailure?.message.contains("Launch already in progress") == true)

        presenter.dismiss()

        let afterDismissFailure = presenter.present(controller: secondController, onWebViewDetach: {}, onFailure: { _ in })
        #expect(afterDismissFailure == nil)
        presenter.dismiss()
    }

}

@MainActor
@Suite(.serialized)
struct WebBridgeViewControllerRuntimeTests {

    @Test func `Dismiss attempt without back stack cancels active UI state`() async throws {
        let cancelSink = CapturedFlowValue<String>()
        let aborts = FlowLocked<[Reason]>([])
        let viewController = makeViewController(
            abortOperation: { reason in aborts.mutate { $0.append(reason) } }
        )
        viewController.loadViewIfNeeded()
        viewController.activeUIState = makeUIState(
            onCancel: { reason in cancelSink.set(reason.description) }
        )
        let presentationController = UIPresentationController(
            presentedViewController: viewController,
            presenting: nil
        )

        viewController.presentationControllerDidAttemptToDismiss(presentationController)

        let cancellation = try await withFlowTimeout("wait for WebBridge cancel callback") {
            await cancelSink.wait()
        }
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
    private weak var host: UIViewController?

    init(host: UIViewController?) {
        self.host = host
    }

    @MainActor
    func activeWindow() -> UIWindow? {
        host?.view.window
    }

    @MainActor
    func topMostViewController(_ window: UIWindow?) -> UIViewController? {
        host
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

private struct WebBridgeViewError: LocalizedError, Sendable {
    let description: String
    var errorDescription: String? { description }
}

private final class CapturingWebBridgeUI: WebBridgeUI, @unchecked Sendable {
    private let startCapture = CapturedFlowValue<Start>()

    func waitForStart() async -> Start {
        await startCapture.wait()
    }

    @MainActor
    func start(
        controller: any WebBridgeOperationController,
        webViewConfiguration: WebBridgeWebViewConfiguration,
        onDetach: @MainActor @escaping () -> Void,
        onStartError: @MainActor @escaping (WebBridgeOperationFailure.UI) -> Void
    ) -> WebBridgeOperationFailure.UI? {
        startCapture.set(
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
