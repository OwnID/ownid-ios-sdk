import Foundation
import Testing

@testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct WebBridgeElitePluginRuntimeTests {
    private let coder = WebBridgeTestJSONCoder()

    @Test func `FLOW provider wrappers capture params and return logged-in status`() async throws {
        let sessionCreate = RecordingWebBridgeSessionCreate()
        let passwordAuthenticate = RecordingWebBridgePasswordAuthenticate()
        let plugin = makePlugin(sessionCreate: sessionCreate, passwordAuthenticate: passwordAuthenticate)

        let sessionResult = await handleWebBridgePlugin(
            plugin,
            pluginID: "FLOW",
            action: "session_create",
            params: Self.sessionCreatePayload
        )
        let passwordResult = await handleWebBridgePlugin(
            plugin,
            pluginID: "flow",
            action: "AUTH_PASSWORD_AUTHENTICATE",
            params: Self.passwordAuthenticatePayload
        )
        let sessionParams = try #require(sessionCreate.createParams.first)
        let passwordParams = try #require(passwordAuthenticate.authenticateParams.first)

        #expect(sessionResult.success?["status"] == .string("logged-in"))
        #expect(sessionResult.error == nil)
        #expect(sessionCreate.events == ["available", "create"])
        #expect(sessionParams.loginID == LoginID(id: "person@example.test", type: .email))
        #expect(sessionParams.accessToken == AccessToken(token: "access-token"))
        #expect(sessionParams.authMethod == .passkey)
        #expect(sessionParams.sessionPayload == #"{"host":"session"}"#)

        #expect(passwordResult.success?["status"] == .string("logged-in"))
        #expect(passwordResult.error == nil)
        #expect(passwordAuthenticate.events == ["available", "authenticate"])
        #expect(passwordParams.loginID == LoginID(id: "person@example.test", type: .email))
        #expect(passwordParams.password == "correct horse battery staple")
    }

    @Test func `FLOW provider failures and unavailable providers return source-defined failure payloads`() async throws {
        let failedSession = RecordingWebBridgeSessionCreate(createResult: .failure(WebBridgePluginRuntimeError("session rejected")))
        let unavailablePassword = RecordingWebBridgePasswordAuthenticate(available: false)
        let plugin = makePlugin(sessionCreate: failedSession, passwordAuthenticate: unavailablePassword)
        let noProviderPlugin = makePlugin(sessionCreate: nil, passwordAuthenticate: nil)

        let sessionResult = await handleWebBridgePlugin(
            plugin,
            pluginID: "FLOW",
            action: "session_create",
            params: Self.sessionCreatePayload
        )
        let passwordResult = await handleWebBridgePlugin(
            plugin,
            pluginID: "FLOW",
            action: "auth_password_authenticate",
            params: Self.passwordAuthenticatePayload
        )
        let missingProviderError = try await handleWebBridgePluginError(
            noProviderPlugin,
            pluginID: "FLOW",
            action: "session_create",
            params: Self.sessionCreatePayload,
            coder: coder
        )

        #expect(sessionResult.success?["status"] == .string("fail"))
        #expect(sessionResult.success?["reason"] == .string("session rejected"))
        #expect(failedSession.events == ["available", "create"])
        #expect(passwordResult.success?["status"] == .string("fail"))
        #expect(passwordResult.success?["reason"] == .string("PasswordAuthenticate is unavailable"))
        #expect(unavailablePassword.events == ["available"])
        #expect(missingProviderError["message"]?.stringValue?.contains("Unknown action: session_create") == true)
    }

    @Test func `FLOW malformed params return bridge error before provider invocation`() async throws {
        let sessionCreate = RecordingWebBridgeSessionCreate()
        let passwordAuthenticate = RecordingWebBridgePasswordAuthenticate()
        let plugin = makePlugin(sessionCreate: sessionCreate, passwordAuthenticate: passwordAuthenticate)

        let missingSessionParamsError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FLOW",
            action: "session_create",
            coder: coder
        )
        let missingPasswordError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FLOW",
            action: "auth_password_authenticate",
            params: #"{"loginId":"person@example.test"}"#,
            coder: coder
        )

        #expect(missingSessionParamsError["message"]?.stringValue?.contains("WebBridgeElitePlugin:") == true)
        #expect(missingPasswordError["message"]?.stringValue?.contains("WebBridgeElitePlugin:") == true)
        #expect(sessionCreate.events.isEmpty)
        #expect(passwordAuthenticate.events.isEmpty)
    }

    @Test func `FLOW operation wrapper success invokes side effect after wrapped function`() async throws {
        let events = FlowLocked<[String]>([])
        let sideEffect = CapturedFlowValue<WebBridgeOperationEventWrapperID>()
        let wrapper = RecordingWebBridgeEventWrapper(
            action: "onFinish",
            result: .bool(true),
            events: events
        )
        let plugin = makePlugin(sessionCreate: nil, passwordAuthenticate: nil)
        plugin.addEventWrappers([wrapper])
        plugin.setWrapperSideEffect { wrapper in
            events.mutate { $0.append("sideEffect") }
            sideEffect.set(WebBridgeOperationEventWrapperID(wrapper.webBridgePluginAction))
        }

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "FLOW",
            action: "onFinish",
            params: #"{"loginId":"person@example.test"}"#
        )
        let sideEffectWrapper = try await withFlowTimeout("FLOW wrapper side effect") {
            await sideEffect.wait()
        }

        #expect(result.success == .bool(true))
        #expect(result.error == nil)
        #expect(wrapper.params == [#"{"loginId":"person@example.test"}"#])
        #expect(sideEffectWrapper.action == "onFinish")
        #expect(events.get() == ["run", "sideEffect"])
    }

    @Test func `FLOW operation wrapper failure returns error without invoking side effect`() async throws {
        let events = FlowLocked<[String]>([])
        let wrapper = RecordingWebBridgeEventWrapper(
            action: "onClose",
            failure: WebBridgePluginRuntimeError("callback failed"),
            events: events
        )
        let plugin = makePlugin(sessionCreate: nil, passwordAuthenticate: nil)
        let sideEffects = FlowLocked<[String]>([])
        plugin.addEventWrappers([wrapper])
        plugin.setWrapperSideEffect { wrapper in
            sideEffects.mutate { $0.append(wrapper.webBridgePluginAction) }
        }

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "FLOW",
            action: "onClose",
            coder: coder
        )

        #expect(error["message"]?.stringValue?.contains("callback failed") == true)
        #expect(error["type"] == .string("UNKNOWN"))
        #expect(wrapper.params == [nil])
        #expect(events.get() == ["run"])
        #expect(sideEffects.get().isEmpty)
    }

    private func makePlugin(
        sessionCreate: (any SessionCreate)?,
        passwordAuthenticate: (any PasswordAuthenticate)?
    ) -> WebBridgeElitePlugin {
        WebBridgeElitePlugin(
            sessionCreate: sessionCreate,
            passwordAuthenticate: passwordAuthenticate,
            loginIDValidator: WebBridgePluginMatrixLoginIDValidator(),
            coder: coder
        )
    }

    private static let sessionCreatePayload =
        #"{"session":{"host":"session"},"metadata":{"loginId":"person@example.test","authToken":"access-token","authMethod":"passkey"}}"#

    private static let passwordAuthenticatePayload =
        #"{"loginId":"person@example.test","password":"correct horse battery staple"}"#
}

private final class RecordingWebBridgeSessionCreate: SessionCreate, @unchecked Sendable {
    private let lock = NSLock()
    private let available: Bool
    private let createResult: Result<SessionOutput, any Error & Sendable>
    private var recordedEvents: [String] = []
    private var recordedCreateParams: [SessionCreateParams] = []

    init(
        available: Bool = true,
        createResult: Result<SessionOutput, any Error & Sendable> = .success(SessionOutput(session: "session"))
    ) {
        self.available = available
        self.createResult = createResult
    }

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    var createParams: [SessionCreateParams] {
        lock.withLock { recordedCreateParams }
    }

    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        lock.withLock { recordedEvents.append("available") }
        return available
    }

    @MainActor func create(params: SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable> {
        lock.withLock {
            recordedEvents.append("create")
            recordedCreateParams.append(params)
        }
        return createResult
    }
}

private final class RecordingWebBridgePasswordAuthenticate: PasswordAuthenticate, @unchecked Sendable {
    private let lock = NSLock()
    private let available: Bool
    private let authenticateResult: Result<SessionOutput, any Error & Sendable>
    private var recordedEvents: [String] = []
    private var recordedAuthenticateParams: [PasswordAuthenticateParams] = []

    init(
        available: Bool = true,
        authenticateResult: Result<SessionOutput, any Error & Sendable> = .success(SessionOutput(session: "session"))
    ) {
        self.available = available
        self.authenticateResult = authenticateResult
    }

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    var authenticateParams: [PasswordAuthenticateParams] {
        lock.withLock { recordedAuthenticateParams }
    }

    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        lock.withLock { recordedEvents.append("available") }
        return available
    }

    @MainActor func authenticate(params: PasswordAuthenticateParams) async -> Result<SessionOutput, any Error & Sendable> {
        lock.withLock {
            recordedEvents.append("authenticate")
            recordedAuthenticateParams.append(params)
        }
        return authenticateResult
    }
}

private struct RecordingWebBridgeEventWrapper: WebBridgeOperationEventWrapper {
    let webBridgePluginAction: String
    let isTerminal = true

    private let result: JSONValue
    private let failure: (any Error)?
    private let events: FlowLocked<[String]>
    private let recordedParams = FlowLocked<[String?]>([])

    init(
        action: String,
        result: JSONValue = .dictionary([:]),
        failure: (any Error)? = nil,
        events: FlowLocked<[String]>
    ) {
        self.webBridgePluginAction = action
        self.result = result
        self.failure = failure
        self.events = events
    }

    var params: [String?] {
        recordedParams.get()
    }

    func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        events.mutate { $0.append("run") }
        recordedParams.mutate { $0.append(params) }
        if let failure {
            throw failure
        }
        return result
    }
}

private struct WebBridgeOperationEventWrapperID: Sendable {
    let action: String

    init(_ action: String) {
        self.action = action
    }
}

private struct WebBridgePluginRuntimeError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
