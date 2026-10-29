import Foundation
import LocalAuthentication
import Testing
import UIKit
import WebKit

@_spi(OwnIDInternal) @testable import OwnIDCore

final class WebBridgeTestJSONCoder: JSONCoder, @unchecked Sendable {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    private let lock = NSLock()

    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data = try lock.withLock { try encoder.encode(value) }
        return try #require(String(data: data, encoding: .utf8))
    }

    func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        let data = try #require(string.data(using: .utf8))
        return try lock.withLock { try decoder.decode(type, from: data) }
    }

    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try lock.withLock { try encoder.encode(value) }
        return try lock.withLock { try decoder.decode(JSONValue.self, from: data) }
    }

    func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T {
        let data = try lock.withLock { try encoder.encode(element) }
        return try lock.withLock { try decoder.decode(type, from: data) }
    }
}

@MainActor
func handleWebBridgePlugin(
    _ plugin: any WebBridgePlugin,
    pluginID: String,
    action: String,
    params: String? = nil
) async -> WebBridgePluginResult {
    await withWebBridgePluginMessage(pluginID: pluginID, action: action, params: params) { message in
        await plugin.handle(message)
    }
}

@MainActor
func handleWebBridgePluginError(
    _ plugin: any WebBridgePlugin,
    pluginID: String,
    action: String,
    params: String? = nil,
    coder: JSONCoder
) async throws -> JSONValue {
    let result = await handleWebBridgePlugin(plugin, pluginID: pluginID, action: action, params: params)
    return try webBridgeErrorPayload(from: result, coder: coder)
}

@MainActor
func withWebBridgePluginMessage<Result>(
    pluginID: String,
    action: String,
    params: String? = nil,
    sourceOrigin: URL = URL(string: "https://login.example.test")!,
    allowedOriginRules: Set<String> = ["https://login.example.test"],
    _ body: (WebBridgePluginMessage) async throws -> Result
) async rethrows -> Result {
    let webView = makeWebBridgeTestWebView()
    defer { tearDownWebBridgeTestWebView(webView) }
    let message = WebBridgePluginMessage(
        webView: webView,
        sourceOrigin: sourceOrigin,
        isMainFrame: true,
        allowedOriginRules: allowedOriginRules,
        payload: .init(pluginID: pluginID, action: action, callbackPath: "OwnID.callback", params: params)
    )
    return try await body(message)
}

@MainActor
func makeWebBridgeTestWebView(
    configure: (WKWebViewConfiguration) -> Void = { _ in }
) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController = WKUserContentController()
    configuration.websiteDataStore = .nonPersistent()
    configure(configuration)
    return WKWebView(frame: .zero, configuration: configuration)
}

@MainActor
func tearDownWebBridgeTestWebView(_ webView: WKWebView) {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeAllUserScripts()
}

@MainActor
final class WebBridgeTestUIContextProvider: UIContextProvider, @unchecked Sendable {
    var result: UIContextResult

    init(result: UIContextResult) {
        self.result = result
    }

    convenience init(window: UIWindow) {
        self.init(result: .windowOnly(window))
    }

    convenience init(window: UIWindow, controller: UIViewController) {
        self.init(result: .windowAndController(window: window, controller: controller))
    }

    func current() -> UIContextResult {
        result
    }
}

/// Keeps page-executing fixtures in a visible view hierarchy until their callbacks finish.
@MainActor
final class WebBridgeTestWebViewHost {
    let window: UIWindow
    let controller: UIViewController
    private weak var webView: WKWebView?

    init(_ webView: WKWebView) {
        self.webView = webView
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        controller = UIViewController()
        window.rootViewController = controller
        controller.view.frame = window.bounds
        webView.frame = controller.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(webView)
        window.isHidden = false
        controller.view.layoutIfNeeded()
    }

    func tearDown() {
        webView?.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
func loadWebBridgeTestHTML(
    _ html: String,
    baseURL: URL,
    in webView: WKWebView
) async throws {
    try Task.checkCancellation()
    let previousNavigationDelegate = webView.navigationDelegate
    defer { webView.navigationDelegate = previousNavigationDelegate }

    let navigationProbe = WebBridgeTestNavigationProbe()
    webView.navigationDelegate = navigationProbe
    webView.stopLoading()
    webView.loadHTMLString(html, baseURL: baseURL)
    do {
        try await navigationProbe.waitForFinish("WebBridge HTML navigation: \(baseURL.absoluteString)")
    } catch {
        webView.stopLoading()
        throw error
    }
}

@MainActor
@discardableResult
func evaluateWebBridgeTestJavaScript(
    _ script: String,
    in webView: WKWebView,
    seconds: UInt64 = 5
) async throws -> String? {
    try Task.checkCancellation()
    let results = AsyncSignalRecorder<Result<String?, any Error>>()
    webView.evaluateJavaScript(script) { result, error in
        if let error {
            results.append(.failure(error))
        } else {
            results.append(.success(result as? String))
        }
    }
    return try await results.waitForFirst("WebBridge JavaScript evaluation", seconds: seconds) { _ in true }.get()
}

final class WebBridgeScriptCallbackProbe: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    static let handlerName = "__ownidTestCallback"

    let handlerName: String

    private let messages = AsyncSignalRecorder<String>()

    init(handlerName: String = WebBridgeScriptCallbackProbe.handlerName) {
        self.handlerName = handlerName
    }

    func waitForMessage(_ description: String = "WebBridge script callback") async throws -> String {
        try await messages.waitForFirst(description) { _ in true }
    }

    func waitForMessageCount(_ count: Int) async throws -> [String] {
        try await messages.waitForCount(count, "WebBridge script callback count \(count)") { _ in true }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            messages.append(body)
        } else {
            messages.append(String(describing: message.body))
        }
    }
}

func webBridgeTestLogRouter(sink: LogCapture) -> OwnIDLogRouter {
    testLogRouter(sink: sink, category: "WebBridgeTests")
}

func webBridgeErrorPayload(
    from result: WebBridgePluginResult,
    coder: JSONCoder
) throws -> JSONValue {
    let encoded = try coder.decodeFromString(result.toResultString(coder: coder), as: JSONValue.self)
    return try #require(encoded["error"])
}

final class WebBridgeFixturePlugin: WebBridgePlugin, @unchecked Sendable {
    let key: WebBridgePluginKey
    let actions: [String]
    let marker: String

    init(id: String, actions: [String] = ["get"], marker: String = "") {
        self.key = WebBridgePluginKey(id: id)
        self.actions = actions
        self.marker = marker.isEmpty ? self.key.id : marker
    }

    func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        .success(nil)
    }
}

private enum WebBridgeTestNavigationResult: Sendable {
    case finished
    case failed(String)
}

private enum WebBridgeTestNavigationError: Error, Sendable {
    case failed(String)
}

final class WebBridgeTestNavigationProbe: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private let results = AsyncSignalRecorder<WebBridgeTestNavigationResult>()

    func waitForFinish(_ description: String = "WebBridge HTML navigation", seconds: UInt64 = 10) async throws {
        switch try await results.waitForFirst(description, seconds: seconds, where: { _ in true }) {
        case .finished:
            return
        case .failed(let message):
            throw WebBridgeTestNavigationError.failed(message)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        results.append(.finished)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        results.append(.failed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        results.append(.failed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        results.append(.failed("WebBridge test web content process terminated"))
    }
}

enum WebBridgeFactoryError: Error {
    case expected
}

final class EmptyWebBridgeResolver: DIContainerResolver {
    let scopeName = "webbridge-plugin-store-tests"

    func canResolve(_ type: Any.Type) -> Bool {
        false
    }

    func getUnsatisfiedDependencies(for type: Any.Type) -> [String]? {
        ["Missing \(type)"]
    }

    func getOrThrow<T: Any & Sendable>(type: T.Type) throws -> T {
        throw WebBridgeFactoryError.expected
    }

    func getOrNil<T: Any & Sendable>(type: T.Type) -> T? {
        nil
    }

    func getAllInstancesOf(where matchesType: @Sendable (Any.Type) -> Bool) -> [any Sendable] {
        []
    }
}

struct WebBridgePluginMatrixLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [(name: "core", version: "test")]
    let bundleID = "com.ownid.webbridge.tests"
    let appVersion = "1"
    let userAgent = "OwnID WebBridge Test"
    let correlationId = "correlation-webbridge-test"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let biometryType: LABiometryType = .none
    let isBiometryUsable = false
    let isBiometryEnrolled: Bool? = nil
    let isBiometryLockedOut: Bool? = nil
    let biometryLocalizedName: String? = nil
    let biometryIconSystemName: String? = nil
    let isPasscodeSet: Bool? = true
}

struct WebBridgeRuntimePluginLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [(name: "core", version: "test")]
    let bundleID = "com.ownid.webbridge.plugin.tests"
    let appVersion = "1"
    let userAgent = "OwnID WebBridge Plugin Test"
    let correlationId: String
    let isDebuggable = true
    let isSystemFidoCapable: Bool
    let biometryType: LABiometryType = .none
    let isBiometryUsable = false
    let isBiometryEnrolled: Bool? = nil
    let isBiometryLockedOut: Bool? = nil
    let biometryLocalizedName: String? = nil
    let biometryIconSystemName: String? = nil
    let isPasscodeSet: Bool? = true

    init(correlationId: String = "correlation-webbridge-plugin-test", isSystemFidoCapable: Bool = true) {
        self.correlationId = correlationId
        self.isSystemFidoCapable = isSystemFidoCapable
    }
}

struct WebBridgePluginMatrixLoginIDValidator: LoginIDValidator {
    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        .email
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        loginID
    }
}

final class WebBridgePluginMatrixUserRepository: UserRepository, @unchecked Sendable {
    func lastUser() async throws -> User? {
        fatalError("Unexpected repository read")
    }

    func setLastUser(_ user: User) async throws {
        fatalError("Unexpected repository write")
    }

    func clearLastUser() async {
        fatalError("Unexpected repository clear")
    }
}

@available(iOS 16.0, *)
final class WebBridgePluginMatrixPasskey: PasskeyProtocol, @unchecked Sendable {
    @MainActor func getCredential(window: UIWindow, assertionOptions: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        fatalError("Unexpected passkey assertion")
    }

    @MainActor func createCredential(window: UIWindow, attestationOptions: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        fatalError("Unexpected passkey attestation")
    }
}

final class WebBridgePluginMatrixAppleSignInProvider: AppleSignInProvider, @unchecked Sendable {
    @MainActor func signIn(window: UIWindow, params: SocialSignInParams) async -> SocialSignInResult {
        fatalError("Unexpected Sign in with Apple")
    }

    @MainActor func cancel() {
        fatalError("Unexpected Apple cancel")
    }
}

final class WebBridgePluginMatrixGoogleSignInProvider: GoogleSignInProvider, @unchecked Sendable {
    @MainActor func signIn(window: UIWindow, params: SocialSignInParams) async -> SocialSignInResult {
        fatalError("Unexpected Sign in with Google")
    }

    @MainActor func cancel() {
        fatalError("Unexpected Google cancel")
    }

    @MainActor func signOut() {
        fatalError("Unexpected Google sign-out")
    }
}

final class WebBridgePluginMatrixSessionCreate: SessionCreate, @unchecked Sendable {
    @MainActor func create(params: SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable> {
        fatalError("Unexpected session create")
    }
}

final class WebBridgePluginMatrixPasswordAuthenticate: PasswordAuthenticate, @unchecked Sendable {
    @MainActor func authenticate(params: PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable> {
        fatalError("Unexpected password authenticate")
    }
}

struct WebBridgePluginMatrixEventWrapper: WebBridgeOperationEventWrapper {
    let action: String
    let isTerminal = true
    var webBridgePluginAction: String { action }

    func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        .dictionary([:])
    }
}
