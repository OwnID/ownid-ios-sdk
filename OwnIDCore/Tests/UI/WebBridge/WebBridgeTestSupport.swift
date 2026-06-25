import Foundation
import Testing
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
func loadWebBridgeTestHTML(
    _ html: String,
    baseURL: URL,
    in webView: WKWebView
) async throws {
    let previousNavigationDelegate = webView.navigationDelegate
    defer { webView.navigationDelegate = previousNavigationDelegate }

    let maxAttempts = 3
    var lastError: (any Error)?
    for attempt in 1...maxAttempts {
        let navigationProbe = WebBridgeTestNavigationProbe()
        webView.navigationDelegate = navigationProbe
        webView.stopLoading()
        webView.loadHTMLString(html, baseURL: baseURL)
        do {
            try await withFlowTimeout("wait for WebBridge test HTML load attempt \(attempt)", seconds: 10) {
                try await navigationProbe.waitForFinish()
            }
            return
        } catch let error as FlowTestTimeout {
            lastError = error
            guard attempt < maxAttempts else { break }
        } catch {
            throw error
        }
    }
    throw lastError ?? FlowTestTimeout.timedOut("wait for WebBridge test HTML load")
}

@MainActor
@discardableResult
func evaluateWebBridgeTestJavaScript(
    _ script: String,
    in webView: WKWebView
) async throws -> String? {
    try await withCheckedThrowingContinuation { continuation in
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: result as? String)
            }
        }
    }
}

final class WebBridgeScriptCallbackProbe: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    static let handlerName = "__ownidTestCallback"

    let handlerName: String

    private let message = CapturedFlowValue<String>()

    init(handlerName: String = WebBridgeScriptCallbackProbe.handlerName) {
        self.handlerName = handlerName
    }

    func waitForMessage() async -> String {
        await message.wait()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            self.message.set(body)
        } else {
            self.message.set(String(describing: message.body))
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

private final class WebBridgeTestNavigationProbe: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private let result = CapturedFlowValue<WebBridgeTestNavigationResult>()

    func waitForFinish() async throws {
        switch await result.wait() {
        case .finished:
            return
        case .failed(let message):
            throw WebBridgeTestNavigationError.failed(message)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        result.set(.finished)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        result.set(.failed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        result.set(.failed(error.localizedDescription))
    }
}

enum WebBridgeFactoryError: Error {
    case expected
}

struct EmptyWebBridgeResolver: DIContainerResolver {
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
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = false
}

struct WebBridgeRuntimePluginLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = [(name: "core", version: "test")]
    let bundleID = "com.ownid.webbridge.plugin.tests"
    let appVersion = "1"
    let userAgent = "OwnID WebBridge Plugin Test"
    let correlationId: String
    let isDebuggable = true
    let isSystemFidoCapable: Bool
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = false

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
    @MainActor func getCredential(assertionOptions: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        fatalError("Unexpected passkey assertion")
    }

    @MainActor func createCredential(attestationOptions: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        fatalError("Unexpected passkey attestation")
    }
}

final class WebBridgePluginMatrixSignInWithApple: SignInWithApple, @unchecked Sendable {
    @MainActor func signIn(params: SignInWithSocialParams) async -> SocialResult {
        fatalError("Unexpected Apple sign-in")
    }

    @MainActor func cancel() {
        fatalError("Unexpected Apple cancel")
    }
}

final class WebBridgePluginMatrixSignInWithGoogle: SignInWithGoogle, @unchecked Sendable {
    @MainActor func signIn(params: SignInWithSocialParams) async -> SocialResult {
        fatalError("Unexpected Google sign-in")
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
