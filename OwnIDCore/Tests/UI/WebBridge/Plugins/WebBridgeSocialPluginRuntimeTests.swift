import Foundation
import Testing

@testable import OwnIDCore

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
        let plugin = makePlugin(providerCase.provider.makeProviderSet(provider: provider))

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
            #expect(params.window == nil)
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

    private func makePlugin(_ providers: WebBridgeSocialProviderSet) -> WebBridgeSocialPlugin {
        WebBridgeSocialPlugin(
            signInWithApple: providers.apple,
            signInWithGoogle: providers.google,
            coder: coder
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

    func makeProviderSet(provider: RecordingWebBridgeSocialProvider) -> WebBridgeSocialProviderSet {
        switch self {
        case .apple: .apple(provider)
        case .google: .google(provider)
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

    static func apple(_ provider: RecordingWebBridgeSocialProvider) -> WebBridgeSocialProviderSet {
        WebBridgeSocialProviderSet(apple: provider, google: nil)
    }

    static func google(_ provider: RecordingWebBridgeSocialProvider) -> WebBridgeSocialProviderSet {
        WebBridgeSocialProviderSet(apple: nil, google: provider)
    }
}

private final class RecordingWebBridgeSocialProvider: SignInWithApple, SignInWithGoogle, @unchecked Sendable {
    private let lock = NSLock()
    private let available: Bool
    private let result: SocialResult
    private var recordedEvents: [String] = []
    private var recordedSignInParams: [SignInWithSocialParams] = []

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

    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        lock.withLock { recordedEvents.append("available") }
        return available
    }

    @MainActor func signIn(params: SignInWithSocialParams) async -> SocialResult {
        lock.withLock {
            recordedEvents.append("signIn")
            recordedSignInParams.append(params)
        }
        return result
    }

    @MainActor func cancel() {}

    @MainActor func signOut() {}
}
