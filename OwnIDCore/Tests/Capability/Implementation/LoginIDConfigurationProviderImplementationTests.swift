import Foundation
import Testing

@testable import OwnIDCore

// Covers: MODEL-030
struct LoginIDConfigurationProviderImplementationTests {
    @Test func `Configuration provider normalizes supported types and regexes`() throws {
        let emailExampleRegex = try regex("^[^@]+@example\\.test$")
        let phoneRegex = try regex("^\\+[0-9]{11}$")
        let unsupportedCredentialRegex = try regex("^credential-.+$")
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(
                supportedTypes: [.userName, .email, .userName, .phoneNumber, .email],
                validationRegexes: [
                    .email: emailExampleRegex,
                    .phoneNumber: phoneRegex,
                    .credentialID: unsupportedCredentialRegex,
                ]
            )
        )

        let initial = provider.configuration
        #expect(initial.supportedTypes == [.userName, .email, .phoneNumber])
        #expect(regexPattern(for: .email, in: initial) == emailExampleRegex.pattern)
        #expect(regexPattern(for: .phoneNumber, in: initial) == phoneRegex.pattern)
        #expect(regexPattern(for: .credentialID, in: initial) == nil)

        provider.setServerConfiguration(
            LoginIDConfiguration(
                supportedTypes: [.email, .email, .phoneNumber],
                validationRegexes: [.phoneNumber: phoneRegex, .anonymous: try regex("^anon-.+$")]
            )
        )

        let server = provider.configuration
        #expect(server.supportedTypes == [.email, .phoneNumber])
        #expect(regexPattern(for: .phoneNumber, in: server) == phoneRegex.pattern)
        #expect(regexPattern(for: .anonymous, in: server) == nil)
    }

    @Test func `Configuration provider app override has priority and invalid updates are ignored`() throws {
        let serverPhoneRegex = try regex("^\\+[0-9]{11}$")
        let overrideEmailRegex = try regex("^[^@]+@override\\.test$")
        let provider = LoginIDConfigurationProviderImpl(initialConfiguration: .default)

        provider.setServerConfiguration(
            LoginIDConfiguration(supportedTypes: [.phoneNumber], validationRegexes: [.phoneNumber: serverPhoneRegex])
        )
        #expect(provider.configuration.supportedTypes == [.phoneNumber])

        provider.setConfiguration(
            LoginIDConfiguration(supportedTypes: [.email, .email], validationRegexes: [.email: overrideEmailRegex])
        )
        #expect(provider.configuration.supportedTypes == [.email])
        #expect(regexPattern(for: .email, in: provider.configuration) == overrideEmailRegex.pattern)

        provider.setServerConfiguration(LoginIDConfiguration(supportedTypes: [], validationRegexes: [.email: nil]))
        #expect(provider.configuration.supportedTypes == [.email])

        provider.clearConfiguration()
        #expect(provider.configuration.supportedTypes == [.phoneNumber])
        #expect(regexPattern(for: .phoneNumber, in: provider.configuration) == serverPhoneRegex.pattern)

        provider.setConfiguration(LoginIDConfiguration(supportedTypes: [], validationRegexes: [.email: nil]))
        #expect(provider.configuration.supportedTypes == [.phoneNumber])
    }

    @Test func `Validator resolves raw login IDs in supported type priority order`() throws {
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(
                supportedTypes: [.userName, .email],
                validationRegexes: [.userName: nil, .email: nil]
            )
        )
        let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)

        #expect(try validator.determineLoginIDType(loginID: "person@example.test") == .userName)

        provider.setConfiguration(
            LoginIDConfiguration(
                supportedTypes: [.email, .userName],
                validationRegexes: [.email: nil, .userName: nil]
            )
        )

        #expect(try validator.determineLoginIDType(loginID: "person@example.test") == .email)
    }

    @Test func `Validator uses ASCII default phone rule for inference and fallback validation`() throws {
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(
                supportedTypes: [.phoneNumber],
                validationRegexes: [.phoneNumber: nil]
            )
        )
        let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)
        let acceptedValues = [
            "1234567",
            "+1234567",
            "123456789012345",
            "+123456789012345",
        ]
        let rejectedValues = [
            "123456",
            "+1234567890123456",
            "0234567",
            "+1٢34567",
            "١٢٣٤٥٦٧",
            "＋1234567",
            " 1234567",
            "1234567 ",
            "123 4567",
            "123-4567",
            "1234567\n",
        ]

        for value in acceptedValues {
            #expect(try validator.determineLoginIDType(loginID: value) == .phoneNumber)
            #expect(try validator.validate(LoginID(id: value, type: .phoneNumber)) == LoginID(id: value, type: .phoneNumber))
        }

        for value in rejectedValues {
            let inferenceError = try #require(throws: (any Error).self) {
                _ = try validator.determineLoginIDType(loginID: value)
            }
            #expect(try requireTypeNotSupported(inferenceError) == .loginIDTypeNotSupported)

            let validationError = try #require(throws: (any Error).self) {
                _ = try validator.validate(LoginID(id: value, type: .phoneNumber))
            }
            let validation = try requireValidationFailed(validationError)
            #expect(validation.errorCode == .loginIDValidationFailed)
            #expect(validation.loginID == LoginID(id: value, type: .phoneNumber))
            #expect(validation.regex == LoginIDType.phoneNumber.classificationRegex.pattern)
        }
    }

    @Test func `Validator rejects unsupported typed login IDs and applies regex overrides`() throws {
        let emailExampleRegex = try regex("^[^@]+@example\\.test$")
        let formattedPhoneRegex = try regex("^[0-9]{3}-[0-9]{4}$")
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(
                supportedTypes: [.email],
                validationRegexes: [.email: emailExampleRegex, .phoneNumber: formattedPhoneRegex]
            )
        )
        let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)

        let accepted = try validator.validate(LoginID(id: "person@example.test", type: .email))
        #expect(accepted == LoginID(id: "person@example.test", type: .email))

        let validationError = try #require(throws: (any Error).self) {
            _ = try validator.validate(LoginID(id: "person@other.test", type: .email))
        }
        let validation = try requireValidationFailed(validationError)
        #expect(validation.errorCode == .loginIDValidationFailed)
        #expect(validation.loginID == LoginID(id: "person@other.test", type: .email))
        #expect(validation.regex == emailExampleRegex.pattern)

        let unsupportedError = try #require(throws: (any Error).self) {
            _ = try validator.validate(LoginID(id: "+15555550123", type: .phoneNumber))
        }
        #expect(try requireTypeNotSupported(unsupportedError) == .loginIDTypeNotSupported)

        provider.setConfiguration(
            LoginIDConfiguration(supportedTypes: [.email], validationRegexes: [.email: nil])
        )
        let fallbackAccepted = try validator.validate(LoginID(id: "person@other.test", type: .email))
        #expect(fallbackAccepted == LoginID(id: "person@other.test", type: .email))

        provider.setConfiguration(
            LoginIDConfiguration(supportedTypes: [.phoneNumber], validationRegexes: [.phoneNumber: formattedPhoneRegex])
        )
        #expect(try validator.determineLoginIDType(loginID: "1234567") == .phoneNumber)
        #expect(
            try validator.validate(LoginID(id: "123-4567", type: .phoneNumber))
                == LoginID(id: "123-4567", type: .phoneNumber)
        )

        let overriddenValidationError = try #require(throws: (any Error).self) {
            _ = try validator.validate(LoginID(id: "1234567", type: .phoneNumber))
        }
        #expect(try requireValidationFailed(overriddenValidationError).regex == formattedPhoneRegex.pattern)

        let overriddenInferenceError = try #require(throws: (any Error).self) {
            _ = try validator.determineLoginIDType(loginID: "123-4567")
        }
        #expect(try requireTypeNotSupported(overriddenInferenceError) == .loginIDTypeNotSupported)
    }

    private func regex(_ pattern: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: pattern)
    }

    private func regexPattern(for type: LoginIDType, in configuration: LoginIDConfiguration) -> String? {
        guard let regex = configuration.validationRegexes[type] else { return nil }
        return regex?.pattern
    }

    private func requireValidationFailed(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> (errorCode: ErrorCode, loginID: LoginID, regex: String) {
        guard case LoginIDValidationError.validationFailed(let errorCode, _, let loginID, let regex) = error else {
            return try #require(
                nil as (errorCode: ErrorCode, loginID: LoginID, regex: String)?,
                "Expected validationFailed, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return (errorCode, loginID, regex)
    }

    private func requireTypeNotSupported(
        _ error: any Error,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> ErrorCode {
        guard case LoginIDValidationError.typeNotSupported(let errorCode, _) = error else {
            return try #require(
                nil as ErrorCode?,
                "Expected typeNotSupported, got \(error)",
                sourceLocation: sourceLocation
            )
        }

        return errorCode
    }
}
