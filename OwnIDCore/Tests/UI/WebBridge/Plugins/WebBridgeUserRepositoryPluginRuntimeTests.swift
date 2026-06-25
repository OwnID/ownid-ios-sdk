import Foundation
import Testing

@testable import OwnIDCore

@MainActor
@Suite(.serialized)
struct WebBridgeUserRepositoryPluginRuntimeTests {
    private let coder = WebBridgeTestJSONCoder()

    @Test func `Storage plugin stores trimmed validated user and mapped auth method`() async throws {
        let repository = RecordingWebBridgeUserRepository()
        let plugin = WebBridgeUserRepositoryPlugin(
            userRepository: repository,
            loginIdValidator: WebBridgePluginLoginIDValidator(),
            coder: coder
        )

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "STORAGE",
            action: "setLastUser",
            params: #"{"loginId":"  user@example.test  ","authMethod":"desktop-biometrics"}"#
        )

        #expect(result.success == .dictionary([:]))
        let saved = try #require(await repository.savedUsers.first)
        #expect(saved.loginID == LoginID(id: "user@example.test", type: .email))
        #expect(saved.authMethod == .passkey)
    }

    @Test func `Storage plugin returns stored user and null missing user payloads`() async throws {
        let repository = RecordingWebBridgeUserRepository(
            lastUser: User(loginID: LoginID(id: "stored@example.test", type: .email), authMethod: .socialGoogle)
        )
        let plugin = WebBridgeUserRepositoryPlugin(
            userRepository: repository,
            loginIdValidator: WebBridgePluginLoginIDValidator(),
            coder: coder
        )

        let storedResult = await handleWebBridgePlugin(plugin, pluginID: "STORAGE", action: "getLastUser")
        #expect(storedResult.success?["loginId"] == .string("stored@example.test"))
        #expect(storedResult.success?["authMethod"] == .string("social-google"))

        await repository.setReadOutcome(.success(nil))

        let missingResult = await handleWebBridgePlugin(plugin, pluginID: "STORAGE", action: "getLastUser")
        #expect(missingResult.success == .null)
    }

    @Test(arguments: [
        #"{"authMethod":"password"}"#,
        #"{"loginId":"   "}"#,
        #"not-json"#,
    ])
    func `Storage plugin validates set params before repository write`(_ params: String) async throws {
        let repository = RecordingWebBridgeUserRepository()
        let plugin = WebBridgeUserRepositoryPlugin(
            userRepository: repository,
            loginIdValidator: WebBridgePluginLoginIDValidator(),
            coder: coder
        )

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "STORAGE",
            action: "setLastUser",
            params: params,
            coder: coder
        )

        #expect(error["message"]?.stringValue?.contains("WebBridgeUserRepositoryPlugin") == true)
        #expect(error["type"] == .string("UNKNOWN"))
        #expect(await repository.savedUsers.isEmpty)
    }

    @Test func `Storage plugin maps validator failure to bridge error`() async throws {
        let repository = RecordingWebBridgeUserRepository()
        let plugin = WebBridgeUserRepositoryPlugin(
            userRepository: repository,
            loginIdValidator: WebBridgePluginLoginIDValidator(
                error: .validationFailed(
                    errorCode: .loginIDValidationFailed,
                    message: "invalid login id",
                    loginID: LoginID(id: "bad", type: .email),
                    regex: "^valid$"
                )
            ),
            coder: coder
        )

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "STORAGE",
            action: "setLastUser",
            params: #"{"loginId":"bad"}"#,
            coder: coder
        )

        #expect(error["message"]?.stringValue?.contains("invalid login id") == true)
        #expect(error["type"] == .string("UNKNOWN"))
        #expect(await repository.savedUsers.isEmpty)
    }

    @Test(arguments: WebBridgeRepositoryFailureCase.all)
    func `Storage plugin maps repository failure and cancellation to bridge error`(
        _ testCase: WebBridgeRepositoryFailureCase
    ) async throws {
        let repository = RecordingWebBridgeUserRepository()
        await repository.setReadOutcome(.failure(testCase.error))
        await repository.setWriteOutcome(.failure(testCase.error))
        let plugin = WebBridgeUserRepositoryPlugin(
            userRepository: repository,
            loginIdValidator: WebBridgePluginLoginIDValidator(),
            coder: coder
        )

        let readError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "STORAGE",
            action: "getLastUser",
            coder: coder
        )
        let writeError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "STORAGE",
            action: "setLastUser",
            params: #"{"loginId":"user@example.test"}"#,
            coder: coder
        )

        #expect(readError["message"]?.stringValue?.contains("WebBridgeUserRepositoryPlugin") == true)
        #expect(writeError["message"]?.stringValue?.contains("WebBridgeUserRepositoryPlugin") == true)
        #expect(readError["type"] == .string("UNKNOWN"))
        #expect(writeError["type"] == .string("UNKNOWN"))
    }
}

private actor RecordingWebBridgeUserRepository: UserRepository {
    private var readOutcome: Result<User?, any Error & Sendable>
    private var writeOutcome: Result<Void, any Error & Sendable>
    private(set) var savedUsers: [User] = []

    init(
        lastUser: User? = nil,
        writeOutcome: Result<Void, any Error & Sendable> = .success(())
    ) {
        self.readOutcome = .success(lastUser)
        self.writeOutcome = writeOutcome
    }

    func setReadOutcome(_ outcome: Result<User?, any Error & Sendable>) {
        readOutcome = outcome
    }

    func setWriteOutcome(_ outcome: Result<Void, any Error & Sendable>) {
        writeOutcome = outcome
    }

    func lastUser() async throws -> User? {
        try readOutcome.get()
    }

    func setLastUser(_ user: User) async throws {
        try writeOutcome.get()
        savedUsers.append(user)
    }

    func clearLastUser() async {}
}

private struct WebBridgePluginLoginIDValidator: LoginIDValidator {
    let type: LoginIDType
    let error: LoginIDValidationError?

    init(type: LoginIDType = .email, error: LoginIDValidationError? = nil) {
        self.type = type
        self.error = error
    }

    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        if let error {
            throw error
        }
        return type
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        loginID
    }
}

struct WebBridgeRepositoryFailureCase: CustomStringConvertible, Sendable {
    let description: String
    let error: any Error & Sendable

    static let all: [WebBridgeRepositoryFailureCase] = [
        .init(description: "failure", error: WebBridgeRepositoryError.expected),
        .init(description: "cancellation", error: CancellationError()),
    ]
}

private enum WebBridgeRepositoryError: Error, LocalizedError, Sendable {
    case expected

    var errorDescription: String? {
        "repository failure"
    }
}
