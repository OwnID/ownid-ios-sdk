import Foundation
import Testing

@testable import OwnIDCore

struct LoginIDContextContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Login ID stores raw ID and type without validation or normalization`() throws {
        let loginID = LoginID(id: "  not-an-email  ", type: .email)

        #expect(loginID.id == "  not-an-email  ")
        #expect(loginID.type == .email)
        #expect(loginID == LoginID(id: "  not-an-email  ", type: .email))
        #expect(loginID != LoginID(id: "not-an-email", type: .email))
        #expect(Set([loginID, LoginID(id: "  not-an-email  ", type: .email)]).count == 1)

        let encoded = try modelJSON.data(encoding: loginID)
        let encodedFields = try modelJSON.decoder.decode([String: String].self, from: encoded)
        let decoded = try modelJSON.decoder.decode(LoginID.self, from: encoded)

        #expect(encodedFields == ["id": "  not-an-email  ", "type": "Email"])
        #expect(decoded == loginID)
    }

    @Test func `Login ID type wire values are stable and strict`() throws {
        #expect(LoginIDType.userName.rawValue == "UserName")
        #expect(LoginIDType.email.rawValue == "Email")
        #expect(LoginIDType.phoneNumber.rawValue == "PhoneNumber")
        #expect(LoginIDType.credentialID.rawValue == "CredentialId")
        #expect(LoginIDType.anonymous.rawValue == "Anonymous")
        #expect(LoginIDType.faceKeyPersonID.rawValue == "FaceKeyPersonId")

        #expect(try modelJSON.decoder.decode(LoginIDType.self, from: Data(#""CredentialId""#.utf8)) == .credentialID)
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(LoginIDType.self, from: Data(#""credentialId""#.utf8))
        }
    }

    @Test func `Raw login ID authz context carries raw ID and display metadata`() throws {
        let context = context { builder in
            builder.authz = .start("  raw-user  ")
            builder.accountDisplayName = "Jane Example"
        }

        #expect(context.rawLoginID == "  raw-user  ")
        #expect(context.loginID == nil)
        #expect(context.accessToken == nil)
        #expect(context.accountDisplayName == "Jane Example")
        #expect(
            context.toWebBridgePayload()
                == .dictionary([
                    "authz": .dictionary(["loginId": .string("  raw-user  ")]),
                    "accountDisplayName": .string("Jane Example"),
                ])
        )

        let error = try #require(throws: (any Error).self) {
            try context.loginID(loginIDValidator: nil)
        }
        let missingValidator = try requireMissingLoginIDValidator(error)

        #expect(missingValidator.errorCode == .missingCapabilityProvider)
        #expect(missingValidator.message == "Context.loginID(): LoginIDValidator required")
    }

    @Test func `Typed login ID authz context preserves typed ID and does not require validator`() throws {
        let typedLoginID = LoginID(id: "  typed-user  ", type: .userName)
        let context = context { builder in
            builder.authz = .start(typedLoginID)
        }

        #expect(context.loginID == typedLoginID)
        #expect(context.rawLoginID == nil)
        #expect(context.accessToken == nil)
        #expect(try context.loginID(loginIDValidator: nil) == typedLoginID)
        #expect(context.toWebBridgePayload() == .dictionary(["authz": .dictionary(["loginId": .string("  typed-user  ")])]))
    }

    @Test func `Start with raw ID and type creates typed login ID authz`() throws {
        let context = context { builder in
            builder.authz = .start("person@example.com", type: .email)
        }

        #expect(context.loginID == LoginID(id: "person@example.com", type: .email))
        #expect(context.rawLoginID == nil)
        #expect(context.accessToken == nil)
        #expect(try context.loginID(loginIDValidator: nil) == LoginID(id: "person@example.com", type: .email))
    }

    @Test func `Access token authz context carries token only`() {
        let rawTokenContext = context { builder in
            builder.authz = .fromToken("raw.jwt.value")
        }
        let typedToken = AccessToken(token: "typed.jwt.value")
        let typedTokenContext = context { builder in
            builder.authz = .fromToken(typedToken)
            builder.accountDisplayName = "Token User"
        }

        #expect(rawTokenContext.accessToken == AccessToken(token: "raw.jwt.value"))
        #expect(rawTokenContext.loginID == nil)
        #expect(rawTokenContext.rawLoginID == nil)
        #expect(rawTokenContext.toWebBridgePayload() == .dictionary(["authz": .dictionary(["accessToken": .string("raw.jwt.value")])]))

        #expect(typedTokenContext.accessToken == typedToken)
        #expect(typedTokenContext.loginID == nil)
        #expect(typedTokenContext.rawLoginID == nil)
        #expect(typedTokenContext.accountDisplayName == "Token User")
        #expect(
            typedTokenContext.toWebBridgePayload()
                == .dictionary([
                    "authz": .dictionary(["accessToken": .string("typed.jwt.value")]),
                    "accountDisplayName": .string("Token User"),
                ])
        )
    }

    @Test func `Context build snapshots builder state`() {
        var builder = Context.Builder()
        builder.authz = .start("first@example.com", type: .email)
        builder.accountDisplayName = "First"

        let first = builder.build(scopeName: "first-scope")

        builder.authz = .fromToken("second-token")
        builder.accountDisplayName = "Second"

        let second = builder.build(scopeName: "second-scope")

        #expect(first.loginID == LoginID(id: "first@example.com", type: .email))
        #expect(first.accountDisplayName == "First")
        #expect(first.accessToken == nil)

        #expect(second.accessToken == AccessToken(token: "second-token"))
        #expect(second.accountDisplayName == "Second")
        #expect(second.loginID == nil)
    }

    @Test func `Raw login ID resolution uses validator and maps exposed failure values`() throws {
        let rawLoginIDContext = context { builder in
            builder.authz = .start("raw-login")
        }
        let validationFailedLoginID = LoginID(id: "bad-email", type: .email)

        let resolved = try rawLoginIDContext.loginID(loginIDValidator: StubLoginIDValidator(result: .success(.userName)))
        #expect(resolved == LoginID(id: "raw-login", type: .userName))

        let unsupportedError = try #require(throws: (any Error).self) {
            try rawLoginIDContext.loginID(
                loginIDValidator: StubLoginIDValidator(
                    result: .failure(
                        .typeNotSupported(errorCode: .loginIDTypeNotSupported, message: "Unsupported login ID type")
                    )
                )
            )
        }
        let unsupported = try requireLoginIDTypeNotSupported(unsupportedError)

        #expect(unsupported.errorCode == .loginIDTypeNotSupported)
        #expect(unsupported.message == "Unsupported login ID type")

        let validationError = try #require(throws: (any Error).self) {
            try rawLoginIDContext.loginID(
                loginIDValidator: StubLoginIDValidator(
                    result: .failure(
                        .validationFailed(
                            errorCode: .loginIDValidationFailed,
                            message: "Invalid email",
                            loginID: validationFailedLoginID,
                            regex: #"^\S+@\S+$"#
                        )
                    )
                )
            )
        }
        let validation = try requireLoginIDValidation(validationError)

        #expect(validation.errorCode == .loginIDValidationFailed)
        #expect(validation.message == "Invalid email")
        #expect(validation.loginID == validationFailedLoginID)
        #expect(validation.regex == #"^\S+@\S+$"#)
    }

    private func context(_ build: (inout Context.Builder) -> Void) -> Context {
        var builder = Context.Builder()
        build(&builder)
        return builder.build(scopeName: "test-scope")
    }

    private func requireMissingLoginIDValidator(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> (errorCode: ErrorCode, message: String) {
        guard case LoginIDResolutionError.missingLoginIDValidator(let errorCode, let message) = error else {
            return try #require(
                nil as (errorCode: ErrorCode, message: String)?,
                "Expected missingLoginIDValidator, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return (errorCode, message)
    }

    private func requireLoginIDTypeNotSupported(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> (errorCode: ErrorCode, message: String) {
        guard case LoginIDResolutionError.loginIDTypeNotSupported(let errorCode, let message) = error else {
            return try #require(
                nil as (errorCode: ErrorCode, message: String)?,
                "Expected loginIDTypeNotSupported, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return (errorCode, message)
    }

    private func requireLoginIDValidation(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> (errorCode: ErrorCode, message: String, loginID: LoginID, regex: String) {
        guard case LoginIDResolutionError.loginIDValidation(let errorCode, let message, let loginID, let regex) = error else {
            return try #require(
                nil as (errorCode: ErrorCode, message: String, loginID: LoginID, regex: String)?,
                "Expected loginIDValidation, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return (errorCode, message, loginID, regex)
    }
}

private struct StubLoginIDValidator: LoginIDValidator {
    let result: Result<LoginIDType, LoginIDValidationError>

    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        switch result {
        case .success(let type):
            return type
        case .failure(let error):
            throw error
        }
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        loginID
    }
}
