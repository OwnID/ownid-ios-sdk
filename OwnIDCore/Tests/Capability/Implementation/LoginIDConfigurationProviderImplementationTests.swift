import Foundation
import Testing

@testable import OwnIDCore

// Covers: MODEL-030
struct LoginIDConfigurationProviderImplementationTests {
    @Test func `Configuration provider normalizes supported types and regexes`() throws {
        let emailExampleRegex = try regex("^[^@]+@example\\.test$")
        let phoneRegex = try regex("^\\+[0-9]{11}$")
        let unsupportedCredentialRegex = try regex("^credential-.+$")
        let provider: any LoginIDConfigurationProvider = LoginIDConfigurationProviderImpl(
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
            supportedTypes: [.email, .email, .phoneNumber],
            validationRegexes: [.phoneNumber: phoneRegex, .anonymous: try regex("^anon-.+$")]
        )

        let server = provider.configuration
        #expect(server.supportedTypes == [.email, .phoneNumber])
        #expect(regexPattern(for: .phoneNumber, in: server) == phoneRegex.pattern)
        #expect(regexPattern(for: .anonymous, in: server) == nil)
    }

    @Test func `Manual configuration takes precedence and clearing exposes the latest valid server configuration`() throws {
        let provider = LoginIDConfigurationProviderImpl(initialConfiguration: .default)
        #expect(provider.configuration.supportedTypes == [.email])

        provider.setServerConfiguration(supportedTypes: [.phoneNumber], validationRegexes: [.phoneNumber: try regex("ext-[0-9]+")])
        #expect(provider.configuration.supportedTypes == [.phoneNumber])

        let manualRule = try regex("manual-.+")
        provider.setConfiguration(supportedTypes: [.userName], validationRegexes: [.userName: manualRule])
        let latestServerRule = try regex("server-.+")
        provider.setServerConfiguration(supportedTypes: [.email], validationRegexes: [.email: latestServerRule])
        let invalid = LoginIDConfiguration(supportedTypes: [], validationRegexes: [:])
        provider.setServerConfiguration(supportedTypes: invalid.supportedTypes, validationRegexes: invalid.validationRegexes)
        provider.setConfiguration(supportedTypes: invalid.supportedTypes, validationRegexes: invalid.validationRegexes)
        #expect(provider.configuration.supportedTypes == [.userName])
        #expect(regexPattern(for: .userName, in: provider.configuration) == manualRule.pattern)

        provider.clearConfiguration()
        #expect(provider.configuration.supportedTypes == [.email])
        #expect(regexPattern(for: .email, in: provider.configuration) == latestServerRule.pattern)
    }

    @Test func `Embedded classifiers use supported type order independently of configured rules`() throws {
        let provider = LoginIDConfigurationProviderImpl(initialConfiguration: .default)
        let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)
        let configuredRule = try regex("member-[0-9]+")
        for types: [LoginIDType] in [[.userName, .email], [.email, .userName]] {
            provider.setConfiguration(supportedTypes: types, validationRegexes: [.email: configuredRule, .userName: configuredRule])
            #expect(try validator.determineLoginIDType(loginID: "person@example.test") == types[0])
            #expect(try validator.determineLoginIDType(loginID: "member-123") == .userName)
        }
    }

    @Test func `Validator uses ASCII default phone rule for inference and fallback validation`() throws {
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(supportedTypes: [.phoneNumber])
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
            let inferenceError = try #require(throws: (any Error).self, "Rejected phone value: \(value.debugDescription)") {
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

    @Test func `Configured rules govern typed validation without changing inference`() throws {
        let emailRule = try regex("email:[A-Z]+")
        let userNameRule = try regex("[0-9]{10}")
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(
                supportedTypes: [.email, .userName],
                validationRegexes: [.email: emailRule, .userName: userNameRule]
            )
        )
        let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)
        for (value, type): (String, LoginIDType) in [("email:ADA", .email), ("0123456789", .userName)] {
            #expect(try validator.validate(LoginID(id: value, type: type)) == LoginID(id: value, type: type))
        }
        for (value, type, rule): (String, LoginIDType, NSRegularExpression) in [
            ("person@example.test", .email, emailRule),
            ("member", .userName, userNameRule),
        ] {
            let loginID = LoginID(id: value, type: type)
            let validationError = try #require(throws: (any Error).self) { _ = try validator.validate(loginID) }
            let failure = try requireValidationFailed(validationError)
            #expect(failure.errorCode == .loginIDValidationFailed)
            #expect(failure.loginID == loginID)
            #expect(failure.regex == rule.pattern)
        }
        #expect(try validator.determineLoginIDType(loginID: "person@example.test") == .email)
        #expect(try validator.determineLoginIDType(loginID: "email:ADA") == .userName)
        #expect(try validator.determineLoginIDType(loginID: "member") == .userName)

        provider.setConfiguration(supportedTypes: [.email, .userName], validationRegexes: [.email: emailRule])
        #expect(try validator.determineLoginIDType(loginID: "person@example.test") == .email)
        let unsupportedError = try #require(throws: (any Error).self) {
            _ = try validator.validate(LoginID(id: "+15555550123", type: .phoneNumber))
        }
        #expect(try requireTypeNotSupported(unsupportedError) == .loginIDTypeNotSupported)
    }

    @Test(arguments: [false, true])
    func `Manual configuration uses embedded rules for missing or nil regexes until cleared`(_ serverFirst: Bool) throws {
        let firstServer = LoginIDConfiguration(
            supportedTypes: [.phoneNumber], validationRegexes: [.phoneNumber: try regex("ext-[0-9]+")]
        )
        let latestServer = LoginIDConfiguration(
            supportedTypes: [.email, .phoneNumber], validationRegexes: [.phoneNumber: try regex("account-[0-9]+")]
        )
        let manualConfigurations = [
            LoginIDConfiguration(supportedTypes: [.phoneNumber]),
            LoginIDConfiguration(supportedTypes: [.phoneNumber], validationRegexes: [.phoneNumber: nil]),
        ]
        for manualConfiguration in manualConfigurations {
            let provider = LoginIDConfigurationProviderImpl(initialConfiguration: .default)
            let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)
            if serverFirst {
                provider.setServerConfiguration(supportedTypes: firstServer.supportedTypes, validationRegexes: firstServer.validationRegexes)
            }
            provider.setConfiguration(supportedTypes: manualConfiguration.supportedTypes, validationRegexes: manualConfiguration.validationRegexes)
            provider.setServerConfiguration(supportedTypes: latestServer.supportedTypes, validationRegexes: latestServer.validationRegexes)

            let loginID = LoginID(id: "1234567", type: .phoneNumber)
            #expect(try validator.determineLoginIDType(loginID: loginID.id) == .phoneNumber)
            #expect(try validator.validate(loginID) == loginID)
            for value in ["account-123", "person@example.test"] {
                #expect(throws: LoginIDValidationError.self) { _ = try validator.determineLoginIDType(loginID: value) }
            }
            #expect(throws: LoginIDValidationError.self) {
                _ = try validator.validate(LoginID(id: "account-123", type: .phoneNumber))
            }

            provider.clearConfiguration()
            let serverLoginID = LoginID(id: "account-123", type: .phoneNumber)
            #expect(throws: LoginIDValidationError.self) { _ = try validator.determineLoginIDType(loginID: serverLoginID.id) }
            #expect(try validator.determineLoginIDType(loginID: "1234567") == .phoneNumber)
            #expect(try validator.validate(serverLoginID) == serverLoginID)
            #expect(try validator.determineLoginIDType(loginID: "person@example.test") == .email)
            #expect(throws: LoginIDValidationError.self) { _ = try validator.determineLoginIDType(loginID: "ext-123") }
        }
    }

    @Test func `Configured validation rules match whole values without normalization`() throws {
        let cases: [(String, NSRegularExpression.Options, String, Bool)] = [
            ("a|ab", [], "ab", true),
            ("a+?", [], "aaa", true),
            ("|ab", [], "ab", true),
            ("a*?", [], "", true),
            ("(?=a)", [], "a", false),
            ("a|ab", [], "zab", false),
            ("a|ab", [], "abc", false),
            ("(a|ab)\\1", [], "abab", true),
            ("(?<part>a|ab)\\k<part>", [], "abab", true),
            ("(?=ab)(a|ab)", [], "ab", true),
            ("a|a(?<=a)b", [], "ab", true),
            ("(?>a|ab)", [], "ab", false),
            ("a++a", [], "aa", false),
            ("a$", [], "a\n", false),
            ("a$", [], "a\r\n", false),
            ("a$", [], "a\u{2028}", false),
            (".*?", [], "a\nb", false),
            ("😀|😀x", [], "😀x", true),
            ("é", [], "e\u{301}", false),
            ("e\u{301}", [], "é", false),
            ("a|ab", [], "ａｂ", false),
            ("straße", .caseInsensitive, "STRASSE", true),
            ("(?i)a|ab", [], "AB", true),
            ("(?-i)a|ab", .caseInsensitive, "AB", false),
            ("(?s).*?", [], "a\nb", true),
            ("(?-s).*?", .dotMatchesLineSeparators, "a\nb", false),
            ("(?-x)a # tail", .allowCommentsAndWhitespace, "a # tail", true),
            ("a|ab", .ignoreMetacharacters, "a|ab", true),
            ("a|ab", .ignoreMetacharacters, "ab", false),
            ("a|ab", .ignoreMetacharacters, "xa|ab", false),
            ("a|ab", .ignoreMetacharacters, "a|abx", false),
        ]
        for (pattern, options, value, matches) in cases {
            try expectFullMatch(pattern, options: options, value: value, matches: matches)
        }
    }

    @Test func `Validator preserves compiled regex modes`() throws {
        let cases: [(String, NSRegularExpression.Options, String, Bool)] = [
            ("A|AB", .caseInsensitive, "ab", true),
            ("a | ab", .allowCommentsAndWhitespace, "ab", true),
            (".*?", .dotMatchesLineSeparators, "a\nb", true),
            ("a|a$\\nb", .anchorsMatchLines, "a\nb", true),
            ("|.", [], "\r", false),
            ("|.", .useUnixLineSeparators, "\r", true),
            ("a|a$\\rb", .anchorsMatchLines, "a\rb", true),
            ("a|a$\\rb", [.anchorsMatchLines, .useUnixLineSeparators], "a\rb", false),
            ("a|a\\b'\\bb", [], "a'b", true),
            ("a|a\\b'\\bb", .useUnicodeWordBoundaries, "a'b", false),
            ("A|AB", [.ignoreMetacharacters, .caseInsensitive, .allowCommentsAndWhitespace], "a|ab", true),
            ("A|AB", [.ignoreMetacharacters, .caseInsensitive, .allowCommentsAndWhitespace], "ab", false),
        ]
        for (pattern, options, value, matches) in cases {
            try expectFullMatch(pattern, options: options, value: value, matches: matches)
        }
    }

    @Test func `Rules with trailing comments or escapes have bounded matching behavior`() throws {
        let cases: [(String, NSRegularExpression.Options, String, Bool)] = [
            ("(?x)a # trailing comment", [], "a", true),
            ("a # trailing comment", .allowCommentsAndWhitespace, "a", true),
            ("\\Qab", [], "ab", true),
            ("\\c", [], "c", true),
            ("(?x)a|ab # trailing comment", [], "ab", false),
            ("a|ab # trailing comment", .allowCommentsAndWhitespace, "ab", false),
            ("a|\\Qab", [], "ab", false),
            ("|\\c", [], "c", false),
        ]
        for (pattern, options, value, matches) in cases {
            try expectFullMatch(pattern, options: options, value: value, matches: matches)
        }
    }

    private func expectFullMatch(
        _ pattern: String,
        options: NSRegularExpression.Options,
        value: String,
        matches: Bool,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws {
        let expression = try NSRegularExpression(pattern: pattern, options: options)
        let provider = LoginIDConfigurationProviderImpl(
            initialConfiguration: LoginIDConfiguration(supportedTypes: [.userName], validationRegexes: [.userName: expression])
        )
        let validator = LoginIDValidatorImpl(loginIDConfigurationProvider: provider)
        let loginID = LoginID(id: value, type: .userName)
        if matches {
            #expect(try validator.validate(loginID) == loginID, sourceLocation: sourceLocation)
        } else {
            let validationError = try #require(throws: (any Error).self, sourceLocation: sourceLocation) {
                _ = try validator.validate(loginID)
            }
            let failure = try requireValidationFailed(validationError, sourceLocation: sourceLocation)
            #expect(failure.errorCode == .loginIDValidationFailed, sourceLocation: sourceLocation)
            #expect(failure.loginID == loginID, sourceLocation: sourceLocation)
            #expect(failure.regex == pattern, sourceLocation: sourceLocation)
        }
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
