import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: WB-BRIDGE-240
@MainActor
@Suite(.serialized)
struct WebBridgeSocialPluginRuntimeTests {
    private let coder = WebBridgeTestJSONCoder()

    @Test(arguments: WebBridgeSocialProviderCase.all)
    fileprivate func `SOCIAL plugin maps provider unavailable canceled failed and success results`(
        _ providerCase: WebBridgeSocialProviderCase
    ) async throws {
        let provider = RecordingWebBridgeSocialProvider(
            available: providerCase.available,
            result: providerCase.result
        )
        let expectedWindow = UIWindow(frame: .zero)
        let plugin = makePlugin(
            providerCase.provider.makeProviderSet(provider: provider),
            uiContextProvider: WebBridgeTestUIContextProvider(window: expectedWindow)
        )

        let result = await handleWebBridgePlugin(
            plugin,
            pluginID: "SOCIAL",
            action: providerCase.provider.action,
            params: Self.socialParams
        )

        switch providerCase.expected {
        case .success(let token):
            #expect(result.success == .string(token))
            #expect(result.error == nil)
            #expect(provider.events == ["available", "signIn"])
        case .error(let messageFragment, let type):
            let error = try webBridgeErrorPayload(from: result, coder: coder)
            #expect(error["message"]?.stringValue?.contains(messageFragment) == true)
            #expect(error["type"] == .string(type))
            #expect(provider.events == providerCase.expectedEvents)
        }

        let signInParams = provider.signInParams
        if providerCase.expectedEvents.contains("signIn") {
            let params = try #require(signInParams.first)
            #expect(params.clientID == "web-client-id")
            #expect(params.nonce == "challenge-id")
            #expect(provider.signInWindows.first === expectedWindow)
        } else {
            #expect(signInParams.isEmpty)
        }
    }

    @Test(arguments: WebBridgeSocialProviderKind.all)
    fileprivate func `SOCIAL plugin maps missing provider to unsupported error`(
        _ providerKind: WebBridgeSocialProviderKind
    ) async throws {
        let plugin = makePlugin(.empty)

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "SOCIAL",
            action: providerKind.action,
            params: Self.socialParams,
            coder: coder
        )

        #expect(error["message"]?.stringValue?.contains("\(providerKind.displayName) Sign In is not supported") == true)
        #expect(error["type"] == .string("UNKNOWN"))
    }

    @Test func `SOCIAL plugin validates params before provider sign-in`() async throws {
        let provider = RecordingWebBridgeSocialProvider()
        let plugin = makePlugin(.google(provider))

        let missingParamsError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "SOCIAL",
            action: "Google",
            coder: coder
        )
        let missingClientIDError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "SOCIAL",
            action: "Google",
            params: #"{"challengeId":"challenge-id"}"#,
            coder: coder
        )
        let blankChallengeIDError = try await handleWebBridgePluginError(
            plugin,
            pluginID: "SOCIAL",
            action: "Google",
            params: #"{"clientId":"web-client-id","challengeId":"   "}"#,
            coder: coder
        )

        #expect(missingParamsError["message"]?.stringValue?.contains("Invalid JSON") == true)
        #expect(missingClientIDError["message"]?.stringValue?.contains("Invalid JSON") == true)
        #expect(blankChallengeIDError["message"]?.stringValue?.contains("challengeId") == true)
        #expect(provider.events.isEmpty)
    }

    @Test func `SOCIAL plugin resolves context after availability and logs resolution failure`() async throws {
        let provider = RecordingWebBridgeSocialProvider()
        let logSink = LogCapture()
        let resolutionError = UIContextResolutionError(
            reason: .unavailable,
            message: "The WebBridge WebView is not attached to a window."
        )
        let plugin = makePlugin(
            .google(provider),
            uiContextProvider: WebBridgeTestUIContextProvider(result: .failure(resolutionError)),
            logger: webBridgeTestLogRouter(sink: logSink)
        )

        let error = try await handleWebBridgePluginError(
            plugin,
            pluginID: "SOCIAL",
            action: "Google",
            params: Self.socialParams,
            coder: coder
        )

        #expect(error["type"] == .string("UNKNOWN"))
        #expect(error["message"]?.stringValue?.contains("Cannot resolve a presentation window") == true)
        #expect(provider.events == ["available"])
        #expect(provider.signInParams.isEmpty)
        #expect(logSink.messages.contains { $0.contains("UI context resolution failed") })
        #expect(logSink.entries.contains { $0.causeDescription?.contains("UI context unavailable") == true })
    }

    @Test func `SOCIAL plugin cancels an active provider request exactly once`() async throws {
        let provider = BlockingWebBridgeSocialProvider()
        let plugin = makePlugin(.google(provider))
        let task = Task { @MainActor in
            await handleWebBridgePlugin(
                plugin,
                pluginID: "SOCIAL",
                action: "Google",
                params: Self.socialParams
            )
        }

        _ = try await provider.started.waitForFirst("wait for social provider invocation") { _ in true }
        task.cancel()
        _ = try await provider.cancellationObserved.waitForFirst("wait for social provider cancellation") { _ in true }

        let result = await task.value
        let error = try webBridgeErrorPayload(from: result, coder: coder)
        #expect(error["type"] == .string("ABORTED"))
        #expect(provider.cancelCount == 1)
    }

    @Test func `SOCIAL plugin skips provider invocation and cancellation when already canceled`() async throws {
        let provider = CancellationBeforeInvocationSocialProvider()
        let plugin = makePlugin(.google(provider))
        let task = Task { @MainActor in
            await handleWebBridgePlugin(
                plugin,
                pluginID: "SOCIAL",
                action: "Google",
                params: Self.socialParams
            )
        }

        _ = try await provider.availabilityStarted.waitForFirst("wait for social availability") { _ in true }
        task.cancel()

        let result = await task.value
        let error = try webBridgeErrorPayload(from: result, coder: coder)
        #expect(error["type"] == .string("ABORTED"))
        #expect(provider.signInCount == 0)
        #expect(provider.cancelCount == 0)
    }

    private func makePlugin(
        _ providers: WebBridgeSocialProviderSet,
        uiContextProvider: any UIContextProvider = WebBridgeTestUIContextProvider(window: UIWindow(frame: .zero)),
        logger: OwnIDLogRouter? = nil
    ) -> WebBridgeSocialPlugin {
        WebBridgeSocialPlugin(
            signInWithApple: providers.apple,
            signInWithGoogle: providers.google,
            uiContextProvider: uiContextProvider,
            coder: coder,
            logger: logger
        )
    }

    private static let socialParams = #"{"clientId":"web-client-id","challengeId":"challenge-id"}"#
}

private enum WebBridgeSocialProviderKind: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case apple
    case google

    static let all = Array(allCases)

    var testDescription: String { rawValue }

    var action: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }

    func makeProviderSet<Provider: SignInWithSocial>(provider: Provider) -> WebBridgeSocialProviderSet {
        switch self {
        case .apple:
            guard let provider = provider as? any SignInWithApple else {
                fatalError("Expected an Apple sign-in provider")
            }
            return .apple(provider)
        case .google:
            guard let provider = provider as? any SignInWithGoogle else {
                fatalError("Expected a Google sign-in provider")
            }
            return .google(provider)
        }
    }
}

private struct WebBridgeSocialProviderCase: CustomTestStringConvertible, Sendable {
    let provider: WebBridgeSocialProviderKind
    let description: String
    let available: Bool
    let result: SocialResult
    let expected: ExpectedResult
    let expectedEvents: [String]

    var testDescription: String {
        "\(provider.testDescription) \(description)"
    }

    static let all: [WebBridgeSocialProviderCase] = WebBridgeSocialProviderKind.all.flatMap { provider in
        [
            .init(
                provider: provider,
                description: "unavailable",
                available: false,
                result: .success(id: "provider-user", idToken: "id-token"),
                expected: .error("\(provider.displayName) Sign In is unavailable", "UNKNOWN"),
                expectedEvents: ["available"]
            ),
            .init(
                provider: provider,
                description: "canceled",
                available: true,
                result: .canceled(reason: .userClose(details: "dismissed")),
                expected: .error("Canceled: userClose: dismissed", "ABORTED"),
                expectedEvents: ["available", "signIn"]
            ),
            .init(
                provider: provider,
                description: "failed",
                available: true,
                result: .fail(error: .general("provider failed")),
                expected: .error("provider failed", "UNKNOWN"),
                expectedEvents: ["available", "signIn"]
            ),
            .init(
                provider: provider,
                description: "success",
                available: true,
                result: .success(id: "provider-user", idToken: "id-token"),
                expected: .success("id-token"),
                expectedEvents: ["available", "signIn"]
            ),
        ]
    }

    enum ExpectedResult: Sendable {
        case success(String)
        case error(String, String)
    }
}

private struct WebBridgeSocialProviderSet {
    let apple: (any SignInWithApple)?
    let google: (any SignInWithGoogle)?

    static let empty = WebBridgeSocialProviderSet(apple: nil, google: nil)

    static func apple(_ provider: any SignInWithApple) -> WebBridgeSocialProviderSet {
        WebBridgeSocialProviderSet(apple: provider, google: nil)
    }

    static func google(_ provider: any SignInWithGoogle) -> WebBridgeSocialProviderSet {
        WebBridgeSocialProviderSet(apple: nil, google: provider)
    }
}

private final class RecordingWebBridgeSocialProvider: SignInWithApple, SignInWithGoogle, @unchecked Sendable {
    private let lock = NSLock()
    private let available: Bool
    private let result: SocialResult
    private var recordedEvents: [String] = []
    private var recordedSignInParams: [SignInWithSocialParams] = []
    private var recordedSignInWindows: [UIWindow] = []

    init(
        available: Bool = true,
        result: SocialResult = .success(id: "provider-user", idToken: "id-token")
    ) {
        self.available = available
        self.result = result
    }

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    var signInParams: [SignInWithSocialParams] {
        lock.withLock { recordedSignInParams }
    }

    var signInWindows: [UIWindow] {
        lock.withLock { recordedSignInWindows }
    }

    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        lock.withLock { recordedEvents.append("available") }
        return available
    }

    @MainActor func signIn(window: UIWindow, params: SignInWithSocialParams) async -> SocialResult {
        lock.withLock {
            recordedEvents.append("signIn")
            recordedSignInParams.append(params)
            recordedSignInWindows.append(window)
        }
        return result
    }

    @MainActor func cancel() {}

    @MainActor func signOut() {}
}

@MainActor
private final class BlockingWebBridgeSocialProvider: SignInWithGoogle, @unchecked Sendable {
    let started = AsyncSignalRecorder<Int>()
    let cancellationObserved = AsyncSignalRecorder<Int>()

    private let lock = NSLock()
    private var signInContinuation: CheckedContinuation<SocialResult, Never>?
    private var recordedCancelCount = 0

    var cancelCount: Int {
        lock.withLock { recordedCancelCount }
    }

    func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        true
    }

    func signIn(window: UIWindow, params: SignInWithSocialParams) async -> SocialResult {
        started.append(1)
        return await withCheckedContinuation { continuation in
            lock.withLock { signInContinuation = continuation }
        }
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<SocialResult, Never>? in
            recordedCancelCount += 1
            let continuation = signInContinuation
            signInContinuation = nil
            return continuation
        }
        cancellationObserved.append(cancelCount)
        continuation?.resume(returning: .canceled(reason: .userClose(details: "task canceled")))
    }

    func signOut() {}
}

@MainActor
private final class CancellationBeforeInvocationSocialProvider: SignInWithGoogle, @unchecked Sendable {
    let availabilityStarted = AsyncSignalRecorder<Int>()

    private(set) var signInCount = 0
    private(set) var cancelCount = 0

    func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        availabilityStarted.append(1)
        await waitForTaskCancellation()
        return true
    }

    func signIn(window: UIWindow, params: SignInWithSocialParams) async -> SocialResult {
        signInCount += 1
        return .success(id: "unexpected", idToken: "unexpected")
    }

    func cancel() {
        cancelCount += 1
    }

    func signOut() {}
}
