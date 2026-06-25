import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

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

    init(languageTag: LanguageTag = .default, values: [String: String]) {
        self.languageTag = languageTag
        self.values = values
    }

    func getString(key: String...) -> String? {
        values[key.joined(separator: ".")]
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
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = false
    let isStrongBiometricEnabled = false
}
