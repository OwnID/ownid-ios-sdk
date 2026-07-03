import Foundation

/// Built-in FLOW plugin used by Elite/WebBridge operations.
///
/// This is an internal WebBridge contract for hosted pages, not a stable app-developer API. The plugin starts with
/// provider-backed wrappers from the current scope, accepts additional operation-scoped wrappers before attachment, and
/// exposes only wrapper action names through injection metadata.
///
/// Provider-backed wrappers handle `session_create` and `auth_password_authenticate` when the matching provider is
/// registered. Operation-supplied wrappers bridge Elite callbacks such as native action, finish, error, and close events.
/// On a successful wrapper result, the plugin invokes the side-effect callback so the owning WebBridge operation can
/// react to terminal wrappers and close or settle the native operation. Unknown actions, malformed payloads, unavailable
/// providers, and provider failures are returned as WebBridge error payloads; Swift task cancellation maps to bridge
/// error type `ABORTED`.
internal final class WebBridgeElitePlugin: WebBridgePlugin, @unchecked Sendable {
    internal static let KEY = WebBridgePluginKey(id: "FLOW")

    var key: WebBridgePluginKey { Self.KEY }

    private let coder: any JSONCoder

    private let syncQueue = DispatchQueue(label: "com.ownid.sdk.WebBridgeElitePlugin.syncQueue")
    private var eventWrappers: [any WebBridgeOperationEventWrapper] = []
    private var sideEffect: (@Sendable (any WebBridgeOperationEventWrapper) -> Void)?

    init(
        sessionCreate: (any SessionCreate)?,
        passwordAuthenticate: (any PasswordAuthenticate)?,
        loginIDValidator: any LoginIDValidator,
        coder: any JSONCoder
    ) {
        self.coder = coder

        if let sessionCreate = sessionCreate {
            eventWrappers.append(SessionCreateWrapper(sessionCreate, loginIDValidator: loginIDValidator))
        }

        if let passwordAuthenticate = passwordAuthenticate {
            eventWrappers.append(PasswordAuthenticateWrapper(passwordAuthenticate, loginIDValidator: loginIDValidator))
        }
    }

    var actions: [String] {
        return syncQueue.sync {
            eventWrappers.map(\.webBridgePluginAction)
        }
    }

    func injectionData() -> (String, [String])? {
        let list = actions
        return list.isEmpty ? nil : (key.id, list)
    }

    /// Adds operation-scoped event wrappers before the bridge is attached and injected.
    func addEventWrappers(_ wrappers: [any WebBridgeOperationEventWrapper]) {
        syncQueue.sync {
            self.eventWrappers.append(contentsOf: wrappers)
        }
    }

    /// Registers a callback invoked after a wrapper completes successfully.
    func setWrapperSideEffect(_ callback: @escaping @Sendable (any WebBridgeOperationEventWrapper) -> Void) {
        syncQueue.sync {
            self.sideEffect = callback
        }
    }

    internal func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        await _handle(message)
    }

    private func _handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        guard key.id.caseInsensitiveCompare(message.payload.pluginID) == .orderedSame else {
            return WebBridgePluginResult.error(message: "WebBridgeElitePlugin: Wrong plugin ID: \(message.payload.pluginID)")
        }

        let wrapper: (any WebBridgeOperationEventWrapper)? = syncQueue.sync {
            eventWrappers.first { $0.webBridgePluginAction.caseInsensitiveCompare(message.payload.action) == .orderedSame }
        }

        guard let wrapper = wrapper else {
            return WebBridgePluginResult.error(message: "WebBridgeElitePlugin: Unknown action: \(message.payload.action)")
        }

        do {
            let result = try await wrapper.runWrappedFunction(params: message.payload.params, coder: coder)

            let currentSideEffect: (@Sendable (any WebBridgeOperationEventWrapper) -> Void)? = syncQueue.sync { sideEffect }
            if let callback = currentSideEffect {
                Task { callback(wrapper) }
            }

            return WebBridgePluginResult.success(result)
        } catch is CancellationError {
            return WebBridgePluginResult.error(
                message: "WebBridgeElitePlugin: Canceled",
                type: "ABORTED"
            )
        } catch {
            return WebBridgePluginResult.error(message: "WebBridgeElitePlugin: \(error.localizedDescription)")
        }
    }
}

extension WebBridgeElitePlugin {
    internal static func create(resolver: any DIContainerResolver) throws -> WebBridgeElitePlugin {
        WebBridgeElitePlugin(
            sessionCreate: resolver.getOrNil(type: (any SessionCreate).self),
            passwordAuthenticate: resolver.getOrNil(type: (any PasswordAuthenticate).self),
            loginIDValidator: try resolver.getOrThrow(type: (any LoginIDValidator).self),
            coder: try resolver.getOrThrow(type: (any JSONCoder).self)
        )
    }
}

private actor SessionCreateWrapper: WebBridgeOperationEventWrapper {
    nonisolated let webBridgePluginAction: String = "session_create"
    nonisolated let isTerminal: Bool = false

    private struct Payload: Decodable {
        let loginId: String
        let rawSession: String
        let authToken: String
        let authMethod: AuthMethod

        private enum CodingKeys: String, CodingKey { case session, metadata }
        private enum MetadataKeys: String, CodingKey { case loginId, authToken, authMethod, authType }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let jsonNode = try container.decode(JSONValue.self, forKey: .session)
            let data = try JSONEncoder().encode(jsonNode)
            guard let raw = String(data: data, encoding: .utf8) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [CodingKeys.session], debugDescription: "Failed to convert session JSON to UTF‑8 string")
                )
            }
            self.rawSession = raw

            let meta = try container.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
            self.loginId = try meta.decode(String.self, forKey: .loginId)
            self.authToken = try meta.decode(String.self, forKey: .authToken)
            if let authMethod = try meta.decodeIfPresent(AuthMethod.self, forKey: .authMethod) {
                self.authMethod = authMethod
            } else if let authMethod = try meta.decodeIfPresent(AuthMethod.self, forKey: .authType) {
                self.authMethod = authMethod
            } else {
                throw DecodingError.keyNotFound(
                    MetadataKeys.authMethod,
                    DecodingError.Context(
                        codingPath: meta.codingPath,
                        debugDescription: "Missing 'authMethod' (or legacy 'authType') field in metadata"
                    )
                )
            }
        }
    }

    private let sessionCreate: any SessionCreate
    private let loginIDValidator: any LoginIDValidator

    init(_ sessionCreate: any SessionCreate, loginIDValidator: any LoginIDValidator) {
        self.sessionCreate = sessionCreate
        self.loginIDValidator = loginIDValidator
    }

    func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        let payload: Payload = try coder.decodeFromString(params ?? "{}", as: Payload.self)
        let loginID = try loginIDValidator.appendWithType(payload.loginId)
        let providerParams = SessionCreateParams(
            loginID: loginID,
            accessToken: AccessToken(token: payload.authToken),
            authMethod: payload.authMethod,
            sessionPayload: payload.rawSession
        )
        let result: Result<SessionOutput, any Error & Sendable>
        if await sessionCreate.isAvailable(params: providerParams) {
            result = await sessionCreate.create(params: providerParams)
        } else {
            result = .failure(ProviderUnavailableError(message: "SessionCreate is unavailable"))
        }
        return result.toStatusJSONValue()
    }
}

private actor PasswordAuthenticateWrapper: WebBridgeOperationEventWrapper {
    nonisolated let webBridgePluginAction: String = "auth_password_authenticate"
    nonisolated let isTerminal: Bool = false

    private struct Payload: Decodable {
        let loginId: String
        let password: String
    }

    private let passwordAuthenticate: any PasswordAuthenticate
    private let loginIDValidator: any LoginIDValidator

    init(_ passwordAuthenticate: any PasswordAuthenticate, loginIDValidator: any LoginIDValidator) {
        self.passwordAuthenticate = passwordAuthenticate
        self.loginIDValidator = loginIDValidator
    }

    func runWrappedFunction(params: String?, coder: any JSONCoder) async throws -> JSONValue {
        let payload = try coder.decodeFromString(params ?? "{}", as: Payload.self)
        let loginID = try loginIDValidator.appendWithType(payload.loginId)
        let providerParams = PasswordAuthenticateParams(loginID: loginID, password: payload.password)
        let result: Result<SessionOutput, any Error & Sendable>
        if await passwordAuthenticate.isAvailable(params: providerParams) {
            result = await passwordAuthenticate.authenticate(params: providerParams)
        } else {
            result = .failure(ProviderUnavailableError(message: "PasswordAuthenticate is unavailable"))
        }
        return result.toStatusJSONValue()
    }
}

private struct ProviderUnavailableError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

extension Result where Success == SessionOutput, Failure == any Error & Sendable {
    fileprivate func toStatusJSONValue() -> JSONValue {
        switch self {
        case .success:
            return JSONValue(["status": "logged-in"])
        case .failure(let error):
            return JSONValue([
                "status": "fail",
                "reason": error.localizedDescription,
            ])
        }
    }
}
