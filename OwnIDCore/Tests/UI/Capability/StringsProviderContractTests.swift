import Foundation
import LocalAuthentication
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: LOC-010, LOC-020, LOC-030, STRINGS-RUNTIME-010, STRINGS-RUNTIME-020
struct StringsProviderContractTests {

    @Test func `Strings provider merges exact language and default maps in fallback order`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let exact = LanguageTag(language: "fr", country: "CA")
        let languageOnly = LanguageTag(language: "fr", country: "")
        let languageTagsProvider = ControlledLanguageTagsProvider(tags: [exact])
        let serverRepository = ControlledServerRepository()
        let provider = makeProvider(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: TaskScope(shutdownToken: shutdownToken)
        )
        var iterator = provider.getStrings(params: TestStringsParams()).makeAsyncIterator()

        await serverRepository.waitForSubscriptions(to: [exact, languageOnly, .default])
        serverRepository.yield(["title": "default title", "message": "default message"], for: .default)

        let defaultOnly = try await requireNextValue(from: &iterator)
        #expect(defaultOnly == TestStrings(title: "default title", message: "default message", action: "embedded action"))

        serverRepository.yield(["title": "language title", "action": "language action"], for: languageOnly)

        let languageOnlyMerged = try await requireNextValue(from: &iterator)
        #expect(
            languageOnlyMerged
                == TestStrings(
                    title: "language title",
                    message: "default message",
                    action: "language action"
                )
        )

        serverRepository.yield(["message": "exact message"], for: exact)

        let merged = try await requireNextValue(from: &iterator)
        #expect(merged.title == "language title")
        #expect(merged.message == "exact message")
        #expect(merged.action == "language action")
    }

    @Test func `Strings provider starts with embedded fallbacks and updates from server stream`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let serverRepository = ControlledServerRepository()
        let provider = makeProvider(
            languageTagsProvider: ControlledLanguageTagsProvider(tags: [.default]),
            serverRepository: serverRepository,
            taskScope: TaskScope(shutdownToken: shutdownToken)
        )
        var iterator = provider.getStrings(params: TestStringsParams()).makeAsyncIterator()

        await serverRepository.waitForSubscriptions(to: [.default])
        serverRepository.yield(nil, for: .default)

        let embedded = try await requireNextValue(from: &iterator)
        #expect(embedded == TestStrings.embedded)

        serverRepository.yield(["title": "server title"], for: .default)

        let updated = try await requireNextValue(from: &iterator)
        #expect(updated.title == "server title")
        #expect(updated.message == "embedded message")
        #expect(updated.action == "embedded action")
    }

    @Test func `Verification embedded repositories preserve placeholder messages and fill missing keys`() {
        let email = EmailVerificationStringsEmbeddedRepositoryImpl().fallbackToEmbedded(
            params: EmailVerificationStringsParams(),
            map: [
                "message": "Use %CODE_LENGTH% digits for %LOGIN_ID%",
                "resend": "Send another email",
            ]
        )
        let phone = PhoneVerificationStringsEmbeddedRepositoryImpl().fallbackToEmbedded(
            params: PhoneVerificationStringsParams(),
            map: [
                "title": "Phone title",
                "message": "Text %CODE_LENGTH% to %LOGIN_ID%",
            ]
        )

        #expect(email.title == EmailVerificationStrings.default.title)
        #expect(email.message == "Use %CODE_LENGTH% digits for %LOGIN_ID%")
        #expect(email.resend == "Send another email")
        #expect(email.cancel == EmailVerificationStrings.default.cancel)

        #expect(phone.title == "Phone title")
        #expect(phone.message == "Text %CODE_LENGTH% to %LOGIN_ID%")
        #expect(phone.description == PhoneVerificationStrings.default.description)
        #expect(phone.notYou == PhoneVerificationStrings.default.notYou)
    }

    @Test func `Login ID collect provider emits embedded fallback and server backed updates`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let localInfo = StringsProviderLocalInfo(isSystemFidoCapable: false)
        let languageTagsProvider = ControlledLanguageTagsProvider(tags: [.default])
        let serverLocaleProvider = ControlledServerLocaleDataSourceProvider()
        let provider = LoginIDCollectStringsProviderImpl(
            languageTagsProvider: languageTagsProvider,
            embeddedRepository: LoginIDCollectStringsEmbeddedRepositoryImpl(localInfo: localInfo),
            serverRepository: LoginIDCollectStringsServerRepositoryImpl(
                localInfo: localInfo,
                serverLocaleProvider: serverLocaleProvider
            ),
            taskScope: TaskScope(shutdownToken: shutdownToken)
        )
        var iterator = provider.getStrings(
            params: LoginIDCollectStringsParams(loginIDTypes: [.email, .phoneNumber])
        ).makeAsyncIterator()

        await serverLocaleProvider.waitForSubscriptions(to: [.default])
        serverLocaleProvider.yield(nil, for: .default)

        let embedded = try await requireNextValue(from: &iterator)
        #expect(embedded == LoginIDCollectStrings.default(loginIDTypes: [.email, .phoneNumber], isSystemFidoCapable: false))

        serverLocaleProvider.yield(
            PathLocaleDataSource(
                values: [
                    "steps.login-id-collect.emailOrPhoneNumber.no-biometrics.title": "Server login title",
                    "steps.login-id-collect.emailOrPhoneNumber.no-biometrics.message": "Server login message",
                    "steps.login-id-collect.emailOrPhoneNumber.no-biometrics.placeholder": "Server login placeholder",
                    "steps.login-id-collect.emailOrPhoneNumber.cta": "Server login cta",
                    "steps.login-id-collect.emailOrPhoneNumber.error": "Server login error",
                ]
            ),
            for: .default
        )

        let updated = try await requireNextValue(from: &iterator)
        #expect(updated.title == "Server login title")
        #expect(updated.message == "Server login message")
        #expect(updated.placeholder == "Server login placeholder")
        #expect(updated.cancel == "Cancel")
        #expect(updated.cta == "Server login cta")
        #expect(updated.error == "Server login error")
    }

    private static let loginForms: [(String, [LoginIDType], String, String, String, String)] = [
        ("email", [.email], "email", "Enter your email", "Email", "Enter a valid email"),
        ("phone", [.phoneNumber], "phoneNumber", "Enter your phone number", "Phone number", "Enter a valid phone number"),
        ("username", [.userName], "userName", "Enter your ID number", "ID number", "Enter a valid ID number"),
        ("email or phone", [.email, .phoneNumber], "emailOrPhoneNumber", "Enter your email or phone number", "Email or phone number", "Enter a valid email or phone number"),
        ("email or username", [.email, .userName], "emailOrUserName", "Enter your email or ID number", "Email or ID number", "Enter a valid email or ID number"),
        ("phone or username", [.phoneNumber, .userName], "phoneNumberOrUserName", "Enter your phone or ID number", "Phone or ID number", "Enter a valid phone or ID number"),
        ("all identifiers", [.email, .phoneNumber, .userName], "emailOrPhoneNumberOrUserName", "Enter your email, phone or ID number", "Email, phone or ID number", "Enter a valid email, phone or ID number"),
    ]

    @Test(arguments: StringsProviderContractTests.loginForms)
    func `Login collection factory and embedded defaults honor each form contract`(
        name: String, loginIDTypes: [LoginIDType], serverKey: String, prompt: String, placeholder: String, error: String
    ) throws {
        let params = LoginIDCollectStringsParams(loginIDTypes: loginIDTypes)
        let face = LoginIDCollectStrings(
            title: "Sign In with Face ID", message: prompt, placeholder: placeholder, cancel: "Cancel", cta: "Continue", error: error
        )
        let touch = LoginIDCollectStrings(
            title: "Sign In with Touch ID", message: prompt, placeholder: placeholder, cancel: "Cancel", cta: "Continue", error: error
        )
        let otp = LoginIDCollectStrings(
            title: prompt, message: "to receive a one-time code", placeholder: placeholder, cancel: "Cancel", cta: "Continue", error: error
        )
        #expect(LoginIDCollectStrings.default(loginIDTypes: loginIDTypes, isSystemFidoCapable: true) == face)
        #expect(LoginIDCollectStrings.default(loginIDTypes: loginIDTypes, isSystemFidoCapable: true, isTouchID: true) == touch)
        #expect(LoginIDCollectStrings.default(loginIDTypes: loginIDTypes, isSystemFidoCapable: false) == otp)
        #expect(LoginIDCollectStrings.default(loginIDTypes: loginIDTypes, isSystemFidoCapable: false, isTouchID: true) == otp)
        let mixedTypes = loginIDTypes + loginIDTypes + [.credentialID]
        #expect(LoginIDCollectStrings.default(loginIDTypes: mixedTypes, isSystemFidoCapable: true) == face)
        #expect(LoginIDCollectStrings.default(loginIDTypes: mixedTypes, isSystemFidoCapable: true, isTouchID: true) == touch)
        #expect(LoginIDCollectStrings.default(loginIDTypes: mixedTypes, isSystemFidoCapable: false, isTouchID: true) == otp)

        var scenarios: [(name: String, type: LABiometryType, usable: Bool, enrolled: Bool?, lockedOut: Bool?, expectedTitle: String)] = [
            ("usable Touch ID", .touchID, true, true, false, "Sign In with Touch ID"),
            ("not enrolled Touch ID", .touchID, false, false, false, "Sign In with Touch ID"),
            ("locked out Touch ID", .touchID, false, true, true, "Sign In with Touch ID"),
            ("usable Face ID", .faceID, true, true, false, "Sign In with Face ID"),
            ("unusable Face ID", .faceID, false, false, false, "Sign In with Face ID"),
            ("no biometry", .none, false, nil, nil, "Sign In with Face ID"),
            ("unrecognized native type", try #require(LABiometryType(rawValue: 999)), true, nil, nil, "Sign In with Face ID"),
        ]
        if #available(iOS 17, *) { scenarios.append(("Optic ID", .opticID, true, true, false, "Sign In with Face ID")) }
        for scenario in scenarios {
            let repository = LoginIDCollectStringsEmbeddedRepositoryImpl(localInfo: StringsProviderLocalInfo(
                isSystemFidoCapable: true, biometryType: scenario.type, isBiometryUsable: scenario.usable,
                isBiometryEnrolled: scenario.enrolled, isBiometryLockedOut: scenario.lockedOut
            ))
            let expected = LoginIDCollectStrings(
                title: scenario.expectedTitle, message: prompt, placeholder: placeholder, cancel: "Cancel", cta: "Continue", error: error
            )
            #expect(repository.fallbackToEmbedded(params: params, map: [:]) == expected, "\(name): \(scenario.name)")
            #expect(repository.fallbackToEmbedded(params: params, map: ["title": "Custom title"]).title == "Custom title")
            #expect(repository.fallbackToEmbedded(params: params, map: ["title": ""]).title.isEmpty)
        }
        #expect(LoginIDCollectStringsEmbeddedRepositoryImpl(localInfo: nil).fallbackToEmbedded(params: params, map: [:]) == face)
        let oldSystem = LoginIDCollectStringsEmbeddedRepositoryImpl(
            localInfo: StringsProviderLocalInfo(isSystemFidoCapable: false, biometryType: .touchID, isBiometryUsable: true)
        )
        #expect(oldSystem.fallbackToEmbedded(params: params, map: [:]) == otp)
    }

    @Test(arguments: StringsProviderContractTests.loginForms)
    func `Server login titles select each identifier path and preserve the OTP gate`(
        name: String, loginIDTypes: [LoginIDType], serverKey: String, prompt: String, placeholder: String, error: String
    ) async throws {
        let scenarios: [(name: String, type: LABiometryType, usable: Bool, enrolled: Bool?, lockedOut: Bool?, fido: Bool, expectedTitle: String, expectedMessage: String)] = [
            ("usable Touch ID", .touchID, true, true, false, true, "Touch translation", "Biometric instruction"),
            ("not enrolled Touch ID", .touchID, false, false, false, true, "Touch translation", "Biometric instruction"),
            ("locked out Touch ID", .touchID, false, true, true, true, "Touch translation", "Biometric instruction"),
            ("usable Face ID", .faceID, true, true, false, true, "Legacy translation", "Biometric instruction"),
            ("pre-FIDO usable Touch ID", .touchID, true, true, false, false, "OTP translation", "OTP instruction"),
            ("pre-FIDO not enrolled Touch ID", .touchID, false, false, false, false, "OTP translation", "OTP instruction"),
        ]
        for scenario in scenarios {
            let locales = ControlledServerLocaleDataSourceProvider()
            let repository = LoginIDCollectStringsServerRepositoryImpl(
                localInfo: StringsProviderLocalInfo(
                    isSystemFidoCapable: scenario.fido, biometryType: scenario.type, isBiometryUsable: scenario.usable,
                    isBiometryEnrolled: scenario.enrolled, isBiometryLockedOut: scenario.lockedOut
                ), serverLocaleProvider: locales
            )
            var iterator = repository.getStrings(
                languageTag: .default,
                params: LoginIDCollectStringsParams(loginIDTypes: loginIDTypes + loginIDTypes + [.credentialID])
            ).makeAsyncIterator()
            await locales.waitForSubscriptions(to: [.default])
            locales.yield(PathLocaleDataSource(content: [
                "steps": .dictionary(["login-id-collect": .dictionary([
                    "title-touch-id-ios": .string("Ancestor Touch translation"),
                    serverKey: .dictionary([
                        "title-touch-id-ios": .string("Touch translation"),
                        "title-ios": .string("Legacy translation"),
                        "message": .string("Biometric instruction"),
                        "no-biometrics": .dictionary([
                            "title-ios": .string("OTP translation"), "message": .string("OTP instruction"),
                        ]),
                    ]),
                ])]),
            ]), for: .default)
            let result = try await requireNextValue(from: &iterator)
            #expect(result["title"] == scenario.expectedTitle, "\(name): \(scenario.name)")
            #expect(result["message"] == scenario.expectedMessage, "\(name): \(scenario.name)")
        }
    }

    @Test func `Touch wording keeps unsupported login ID sets empty`() {
        let repository = LoginIDCollectStringsEmbeddedRepositoryImpl(
            localInfo: StringsProviderLocalInfo(isSystemFidoCapable: true, biometryType: .touchID, isBiometryUsable: true)
        )
        let empty = LoginIDCollectStrings(title: "", message: "", placeholder: "", cancel: "", cta: "", error: "")
        for types: [LoginIDType] in [[], [.anonymous, .credentialID]] {
            #expect(LoginIDCollectStrings.default(loginIDTypes: types, isSystemFidoCapable: true, isTouchID: true) == empty)
            #expect(LoginIDCollectStrings.default(loginIDTypes: types, isSystemFidoCapable: false, isTouchID: true) == empty)
            #expect(repository.fallbackToEmbedded(params: LoginIDCollectStringsParams(loginIDTypes: types), map: [:]) == empty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `Touch title uses normal locale fallback across old new and mixed payloads`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }
        let exact = LanguageTag(language: "fr", country: "CA")
        let language = exact.toLanguageOnly()
        let localInfo = StringsProviderLocalInfo(
            isSystemFidoCapable: true, biometryType: .touchID, isBiometryUsable: false, isBiometryEnrolled: false
        )
        let localeProvider = ControlledServerLocaleDataSourceProvider()
        let provider = LoginIDCollectStringsProviderImpl(
            languageTagsProvider: ControlledLanguageTagsProvider(tags: [exact]),
            embeddedRepository: LoginIDCollectStringsEmbeddedRepositoryImpl(localInfo: localInfo),
            serverRepository: LoginIDCollectStringsServerRepositoryImpl(localInfo: localInfo, serverLocaleProvider: localeProvider),
            taskScope: TaskScope(shutdownToken: shutdownToken)
        )
        var iterator = provider.getStrings(params: LoginIDCollectStringsParams(loginIDTypes: [.email])).makeAsyncIterator()
        await localeProvider.waitForSubscriptions(to: [exact, language, .default])
        for tag in [exact, language, .default] {
            localeProvider.yield(PathLocaleDataSource(languageTag: tag, content: [
                "steps": .dictionary(["login-id-collect": .dictionary(["title-ios": .string("ACME legacy Face")])]),
            ]), for: tag)
        }
        #expect(try await requireNextValue(from: &iterator).title == "Sign In with Touch ID")

        localeProvider.yield(PathLocaleDataSource(content: [
            "steps": .dictionary(["login-id-collect": .dictionary(["title-touch-id-ios": .string("English Touch")])]),
        ]), for: .default)
        #expect(try await requireNextValue(from: &iterator).title == "English Touch")

        localeProvider.yield(PathLocaleDataSource(languageTag: language, content: [
            "steps": .dictionary(["login-id-collect": .dictionary(["title-touch-id-ios": .string("French Touch")])]),
        ]), for: language)
        #expect(try await requireNextValue(from: &iterator).title == "French Touch")

        let legacyRegion: [String: JSONValue] = [
            "steps": .dictionary(["login-id-collect": .dictionary([
                "title-ios": .string("ACME regional Face"),
                "email": .dictionary(["message": .string("Regional email prompt")]),
            ])]),
        ]
        localeProvider.yield(PathLocaleDataSource(languageTag: exact, content: legacyRegion), for: exact)
        let mixed = try await requireNextValue(from: &iterator)
        #expect(mixed.title == "French Touch")
        #expect(mixed.message == "Regional email prompt")

        let updatedRegion: [String: JSONValue] = [
            "steps": .dictionary(["login-id-collect": .dictionary([
                "title-ios": .string("ACME regional Face"),
                "title-android": .string("Android fingerprint"),
                "title-touch-id-ios": .string("Regional Touch"),
                "email": .dictionary([
                    "title-touch-id": .string("Shared email Touch"),
                    "title-touch-id-ios": .string("ACME email Touch"),
                ]),
            ])]),
        ]
        localeProvider.yield(PathLocaleDataSource(languageTag: exact, content: updatedRegion), for: exact)
        #expect(try await requireNextValue(from: &iterator).title == "ACME email Touch")
        let legacyLookup = ServerLocaleContent(languageTag: exact, content: updatedRegion)
        #expect(legacyLookup.getString(localeKeys: ["steps", "login-id-collect", "email", "title"]) == "ACME regional Face")

        localeProvider.yield(PathLocaleDataSource(languageTag: exact, content: [
            "steps": .dictionary(["login-id-collect": .dictionary(["title-touch-id-ios": .string("")])]),
        ]), for: exact)
        #expect(try await requireNextValue(from: &iterator).title.isEmpty)

        localeProvider.yield(nil, for: exact)
        #expect(try await requireNextValue(from: &iterator).title == "French Touch")
        localeProvider.yield(nil, for: language)
        #expect(try await requireNextValue(from: &iterator).title == "English Touch")
        localeProvider.yield(nil, for: .default)
        #expect(try await requireNextValue(from: &iterator).title == "Sign In with Touch ID")
    }

    @Test func `Email verification provider emits server backed updates with embedded fallback`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let serverLocaleProvider = ControlledServerLocaleDataSourceProvider()
        let provider = EmailVerificationStringsProviderImpl(
            languageTagsProvider: ControlledLanguageTagsProvider(tags: [.default]),
            embeddedRepository: EmailVerificationStringsEmbeddedRepositoryImpl(),
            serverRepository: EmailVerificationStringsServerRepositoryImpl(serverLocaleProvider: serverLocaleProvider),
            taskScope: TaskScope(shutdownToken: shutdownToken)
        )
        var iterator = provider.getStrings(params: EmailVerificationStringsParams()).makeAsyncIterator()

        await serverLocaleProvider.waitForSubscriptions(to: [.default])
        serverLocaleProvider.yield(
            PathLocaleDataSource(
                values: [
                    "steps.otp.verify.email.title": "Server email title",
                    "steps.otp.email.verify.message": "Server email %CODE_LENGTH% %LOGIN_ID%",
                    "steps.otp.email.verify.resend": "Server email resend",
                ]
            ),
            for: .default
        )

        let first = try await requireNextValue(from: &iterator)
        #expect(first.title == "Server email title")
        #expect(first.message == "Server email %CODE_LENGTH% %LOGIN_ID%")
        #expect(first.description == EmailVerificationStrings.default.description)
        #expect(first.resend == "Server email resend")
        #expect(first.cancel == EmailVerificationStrings.default.cancel)
        #expect(first.notYou == EmailVerificationStrings.default.notYou)

        serverLocaleProvider.yield(
            PathLocaleDataSource(
                values: [
                    "steps.otp.verify.email.title": "Updated email title",
                    "steps.otp.email.verify.message": "Updated email %CODE_LENGTH% %LOGIN_ID%",
                    "steps.otp.email.verify.description": "Updated email description",
                    "steps.otp.email.verify.resend": "Updated email resend",
                    "steps.otp.email.verify.cancel": "Updated email cancel",
                    "steps.otp.email.verify.not-you": "Updated email not you",
                ]
            ),
            for: .default
        )

        let updated = try await requireNextValue(from: &iterator)
        #expect(
            updated
                == EmailVerificationStrings(
                    title: "Updated email title",
                    message: "Updated email %CODE_LENGTH% %LOGIN_ID%",
                    description: "Updated email description",
                    resend: "Updated email resend",
                    cancel: "Updated email cancel",
                    notYou: "Updated email not you"
                )
        )
    }

    @Test func `Phone verification provider emits embedded fallback and server backed updates`() async throws {
        let shutdownToken = ShutdownToken()
        defer { shutdownToken.cancel() }

        let serverLocaleProvider = ControlledServerLocaleDataSourceProvider()
        let provider = PhoneVerificationStringsImpl(
            languageTagsProvider: ControlledLanguageTagsProvider(tags: [.default]),
            embeddedRepository: PhoneVerificationStringsEmbeddedRepositoryImpl(),
            serverRepository: PhoneVerificationStringsServerRepositoryImpl(serverLocaleProvider: serverLocaleProvider),
            taskScope: TaskScope(shutdownToken: shutdownToken)
        )
        var iterator = provider.getStrings(params: PhoneVerificationStringsParams()).makeAsyncIterator()

        await serverLocaleProvider.waitForSubscriptions(to: [.default])
        serverLocaleProvider.yield(nil, for: .default)

        let embedded = try await requireNextValue(from: &iterator)
        #expect(embedded == PhoneVerificationStrings.default)

        serverLocaleProvider.yield(
            PathLocaleDataSource(
                values: [
                    "steps.otp.verify.sms.title": "Server phone title",
                    "steps.otp.sms.verify.message": "Server phone %CODE_LENGTH% %LOGIN_ID%",
                    "steps.otp.sms.verify.description": "Server phone description",
                    "steps.otp.sms.verify.resend": "Server phone resend",
                    "steps.otp.sms.verify.not-you": "Server phone not you",
                ]
            ),
            for: .default
        )

        let updated = try await requireNextValue(from: &iterator)
        #expect(updated.title == "Server phone title")
        #expect(updated.message == "Server phone %CODE_LENGTH% %LOGIN_ID%")
        #expect(updated.description == "Server phone description")
        #expect(updated.resend == "Server phone resend")
        #expect(updated.cancel == PhoneVerificationStrings.default.cancel)
        #expect(updated.notYou == "Server phone not you")
    }

    private func makeProvider(
        languageTagsProvider: ControlledLanguageTagsProvider,
        serverRepository: ControlledServerRepository,
        taskScope: TaskScope
    ) -> StringsProviderImpl<TestStrings, TestStringsParams> {
        StringsProviderImpl<TestStrings, TestStringsParams>(
            languageTagsProvider: languageTagsProvider,
            serverRepository: serverRepository,
            taskScope: taskScope
        ) { _, map in
            TestStrings(
                title: map["title"] ?? TestStrings.embedded.title,
                message: map["message"] ?? TestStrings.embedded.message,
                action: map["action"] ?? TestStrings.embedded.action
            )
        }
    }

    private func requireNextValue<Value>(
        from iterator: inout AsyncStream<Value?>.AsyncIterator,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws -> Value {
        let emission = try #require(await iterator.next(), sourceLocation: sourceLocation)
        return try #require(emission, sourceLocation: sourceLocation)
    }
}

private struct TestStringsParams: StringsParams {}

private struct TestStrings: StringsData, Equatable {
    static let embedded = TestStrings(title: "embedded title", message: "embedded message", action: "embedded action")

    let title: String
    let message: String
    let action: String
}

private final class ControlledLanguageTagsProvider: LanguageTagsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var currentTags: [LanguageTag]
    private var continuations: [AsyncStream<[LanguageTag]>.Continuation] = []

    init(tags: [LanguageTag]) {
        self.currentTags = tags
    }

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            let tags = lock.withLock {
                continuations.append(continuation)
                return currentTags
            }
            continuation.yield(tags)
        }
    }

    func setLanguageTags(_ tags: [String]) {
        let resolved = tags.isEmpty ? [LanguageTag.default] : tags.map { LanguageTag.from(locale: Locale(identifier: $0)) }
        publish(resolved)
    }

    func publish(_ tags: [LanguageTag]) {
        let continuations = lock.withLock {
            currentTags = tags
            return self.continuations
        }
        for continuation in continuations {
            continuation.yield(tags)
        }
    }
}

private final class ControlledServerRepository: ServerRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations = [LanguageTag: [AsyncStream<[String: String]?>.Continuation]]()
    private var waiters: [Waiter] = []

    func getStrings<P: StringsParams>(languageTag: LanguageTag, params: P) -> AsyncStream<[String: String]?> {
        AsyncStream { continuation in
            let continuationsToResume = lock.withLock {
                continuations[languageTag, default: []].append(continuation)
                return popSatisfiedWaiters()
            }
            for continuation in continuationsToResume {
                continuation.resume()
            }
        }
    }

    func yield(_ value: [String: String]?, for languageTag: LanguageTag) {
        let continuations = lock.withLock {
            self.continuations[languageTag] ?? []
        }
        for continuation in continuations {
            continuation.yield(value)
        }
    }

    func waitForSubscriptions(to languageTags: Set<LanguageTag>) async {
        let shouldWait = lock.withLock {
            !languageTags.isSubset(of: Set(continuations.keys))
        }
        guard shouldWait else { return }

        await withCheckedContinuation { continuation in
            let continuationsToResume = lock.withLock {
                waiters.append(Waiter(languageTags: languageTags, continuation: continuation))
                return popSatisfiedWaiters()
            }
            for continuation in continuationsToResume {
                continuation.resume()
            }
        }
    }

    private func popSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {
        let subscribedTags = Set(continuations.keys)
        var ready: [CheckedContinuation<Void, Never>] = []
        waiters.removeAll { waiter in
            guard waiter.languageTags.isSubset(of: subscribedTags) else { return false }
            ready.append(waiter.continuation)
            return true
        }
        return ready
    }

    private struct Waiter {
        let languageTags: Set<LanguageTag>
        let continuation: CheckedContinuation<Void, Never>
    }
}

private final class ControlledServerLocaleDataSourceProvider: ServerLocaleDataSourceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations = [LanguageTag: [AsyncStream<(any ServerLocaleDataSource)?>.Continuation]]()
    private var waiters: [Waiter] = []

    func getDataSource(for languageTag: LanguageTag) -> AsyncStream<(any ServerLocaleDataSource)?> {
        AsyncStream { continuation in
            let continuationsToResume = lock.withLock {
                continuations[languageTag, default: []].append(continuation)
                return popSatisfiedWaiters()
            }
            for continuation in continuationsToResume {
                continuation.resume()
            }
        }
    }

    func yield(_ dataSource: (any ServerLocaleDataSource)?, for languageTag: LanguageTag) {
        let continuations = lock.withLock {
            self.continuations[languageTag] ?? []
        }
        for continuation in continuations {
            continuation.yield(dataSource)
        }
    }

    func waitForSubscriptions(to languageTags: Set<LanguageTag>) async {
        let shouldWait = lock.withLock {
            !languageTags.isSubset(of: Set(continuations.keys))
        }
        guard shouldWait else { return }

        await withCheckedContinuation { continuation in
            let continuationsToResume = lock.withLock {
                waiters.append(Waiter(languageTags: languageTags, continuation: continuation))
                return popSatisfiedWaiters()
            }
            for continuation in continuationsToResume {
                continuation.resume()
            }
        }
    }

    private func popSatisfiedWaiters() -> [CheckedContinuation<Void, Never>] {
        let subscribedTags = Set(continuations.keys)
        var ready: [CheckedContinuation<Void, Never>] = []
        waiters.removeAll { waiter in
            guard waiter.languageTags.isSubset(of: subscribedTags) else { return false }
            ready.append(waiter.continuation)
            return true
        }
        return ready
    }

    private struct Waiter {
        let languageTags: Set<LanguageTag>
        let continuation: CheckedContinuation<Void, Never>
    }
}

private struct PathLocaleDataSource: ServerLocaleDataSource {
    let languageTag: LanguageTag
    let values: [String: String]
    private let content: ServerLocaleContent?

    init(languageTag: LanguageTag = .default, values: [String: String]) {
        self.languageTag = languageTag
        self.values = values
        self.content = nil
    }

    init(languageTag: LanguageTag = .default, content: [String: JSONValue]) {
        self.languageTag = languageTag
        self.values = [:]
        self.content = ServerLocaleContent(languageTag: languageTag, content: content)
    }

    func getString(key: String...) -> String? {
        if let content { return content.getString(localeKeys: key) }
        return values[key.joined(separator: ".")]
    }
}

private struct StringsProviderLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = []
    let bundleID = "com.ownid.tests"
    let appVersion = "1.0"
    let userAgent = "OwnIDCoreTests"
    let correlationId = "correlation-strings-provider-tests"
    let isDebuggable = true
    let isSystemFidoCapable: Bool
    var biometryType: LABiometryType = .none
    var isBiometryUsable = false
    var isBiometryEnrolled: Bool? = nil
    var isBiometryLockedOut: Bool? = nil
    let biometryLocalizedName: String? = nil
    let biometryIconSystemName: String? = nil
    let isPasscodeSet: Bool? = true
}
