import Foundation

/// Internal STORAGE WebBridge plugin backed by the instance ``UserRepository``.
///
/// The plugin exposes the `STORAGE` key with `setLastUser` and `getLastUser` actions. Plugin ID and action matching
/// are case-insensitive. `getLastUser` ignores params and returns the repository value as
/// `{ "loginId": ..., "authMethod": ... }`, or JSON `null` when no user is stored. `setLastUser` expects params JSON
/// with a non-blank `loginId` and optional `authMethod`; it trims, validates, and normalizes the login ID through
/// ``LoginIDValidator``, maps known auth-method aliases, stores a ``User``, and returns an empty JSON object on
/// success. Invalid JSON, missing or invalid login IDs, validation failures, repository failures, wrong plugin IDs, and
/// unknown actions are returned as bridge error payloads. The plugin boundary is limited to last-user repository access
/// and login-ID normalization, and it does not own the underlying persistence policy.
internal actor WebBridgeUserRepositoryPlugin: WebBridgePlugin {
    internal static let KEY = WebBridgePluginKey(id: "STORAGE")

    nonisolated var key: WebBridgePluginKey { Self.KEY }
    nonisolated let actions: [String] = ["setLastUser", "getLastUser"]

    private let userRepository: any UserRepository
    private let loginIdValidator: any LoginIDValidator
    private let coder: any JSONCoder

    init(userRepository: any UserRepository, loginIdValidator: any LoginIDValidator, coder: any JSONCoder) {
        self.userRepository = userRepository
        self.loginIdValidator = loginIdValidator
        self.coder = coder
    }

    nonisolated func handle(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        await handleIsolated(message)
    }

    private func handleIsolated(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        guard key.id.caseInsensitiveCompare(message.payload.pluginID) == .orderedSame else {
            return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: Wrong plugin ID: \(message.payload.pluginID)")
        }

        switch message.payload.action.uppercased() {
        case "SETLASTUSER": return await handleSetLastUser(message)
        case "GETLASTUSER": return await handleGetLastUser(message)
        default: return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: Unknown action: \(message.payload.action)")
        }
    }

    private func handleSetLastUser(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        struct Params: Decodable {
            let loginId: String
            let authMethod: String?
        }

        let params: Params
        do {
            params = try coder.decodeFromString(message.payload.params ?? "{}", as: Params.self)
        } catch {
            return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: Invalid JSON: \(error.localizedDescription)")
        }

        let loginIdString = params.loginId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loginIdString.isEmpty else {
            return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: Missing or invalid 'loginId' parameter")
        }

        let loginID: LoginID
        do {
            loginID = try loginIdValidator.appendWithType(loginIdString)
        } catch let error {
            return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: \(error.message)")
        }

        let authMethod = params.authMethod?.toAuthMethod() ?? .unknown

        let user = User(loginID: loginID, authMethod: authMethod)

        do {
            try await userRepository.setLastUser(user)
            return WebBridgePluginResult.success(JSONValue.dictionary([:]))
        } catch {
            return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: \(error.localizedDescription)")
        }
    }

    private func handleGetLastUser(_ message: WebBridgePluginMessage) async -> WebBridgePluginResult {
        struct WebBridgeUserRepositoryPluginSuccess: Codable {
            let loginId: String
            let authMethod: String?
        }

        do {
            guard let lastUser = try await userRepository.lastUser() else {
                return WebBridgePluginResult.success(JSONValue.null)
            }
            let success = WebBridgeUserRepositoryPluginSuccess(loginId: lastUser.loginID.id, authMethod: lastUser.authMethod.rawValue)
            return WebBridgePluginResult.success(try coder.encodeToJSONValue(success))
        } catch {
            return WebBridgePluginResult.error(message: "WebBridgeUserRepositoryPlugin: \(error.localizedDescription)")
        }
    }
}

extension WebBridgeUserRepositoryPlugin {
    internal static func create(resolver: any DIContainerResolver) throws -> WebBridgeUserRepositoryPlugin {
        WebBridgeUserRepositoryPlugin(
            userRepository: try resolver.getOrThrow(type: (any UserRepository).self),
            loginIdValidator: try resolver.getOrThrow(type: (any LoginIDValidator).self),
            coder: try resolver.getOrThrow(type: (any JSONCoder).self)
        )
    }
}

extension String {
    fileprivate func toAuthMethod() -> AuthMethod {
        switch self.lowercased() {
        case "passkey", "biometrics", "desktop-biometrics": return .passkey
        case "otp", "email-fallback", "sms-fallback": return .otp
        case "password": return .password
        case "social-google": return .socialGoogle
        case "social-apple": return .socialApple
        case "facekey": return .facekey
        case "magic-link": return .magicLink
        case "deferred": return .deferred
        case "immediate": return .immediate
        default: return .unknown
        }
    }
}
