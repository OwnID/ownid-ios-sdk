import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: UI-300
@MainActor
@Suite(.serialized)
struct OperationUIContextAdapterTests {

    @Test func `Passkey assertion forwards the resolved window and options`() async throws {
        let window = makeTestWindow()
        let passkey = RecordingPasskeyCapability()
        let adapter = PasskeyAssertionUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            passkeyProvider: { passkey },
            logger: nil
        )
        let options = testAssertionOptions("adapter-assertion-challenge")

        let result = await adapter.getCredential(options: options)

        #expect(result.isSuccess)
        #expect(passkey.receivedAssertionOptions == options)
        #expect(passkey.receivedWindow === window)
        #expect(passkey.assertionCallCount == 1)
    }

    @Test func `Passkey attestation forwards the resolved window and options`() async throws {
        let window = makeTestWindow()
        let passkey = RecordingPasskeyCapability()
        let adapter = PasskeyAttestationUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            passkeyProvider: { passkey },
            logger: nil
        )
        let options = testAttestationOptions("adapter-attestation-challenge")

        let result = await adapter.createCredential(options: options)

        #expect(result.isSuccess)
        #expect(passkey.receivedAttestationOptions?.challenge == options.challenge)
        #expect(passkey.receivedAttestationOptions?.rp.id == options.rp.id)
        #expect(passkey.receivedAttestationOptions?.rp.name == options.rp.name)
        #expect(passkey.receivedAttestationOptions?.user.id == options.user.id)
        #expect(passkey.receivedAttestationOptions?.user.name == options.user.name)
        #expect(passkey.receivedAttestationOptions?.user.displayName == options.user.displayName)
        #expect(
            passkey.receivedAttestationOptions?.pubKeyCredParams.map { $0.type.description }
                == options.pubKeyCredParams.map { $0.type.description }
        )
        #expect(
            passkey.receivedAttestationOptions?.pubKeyCredParams.map { $0.alg.description }
                == options.pubKeyCredParams.map { $0.alg.description }
        )
        #expect(passkey.receivedWindow === window)
        #expect(passkey.attestationCallCount == 1)
    }

    @Test func `Passkey adapters preserve provider failures and cancellations exactly`() async throws {
        for route in PasskeyAdapterRoute.allCases {
            for terminal in AdapterTerminal.allCases {
                let window = makeTestWindow()
                let cause = NSError(domain: "adapter.passkey.test", code: route.rawValue)
                let reason = Reason.userClose(details: "\(route)-dismissed")
                let passkey: RecordingPasskeyCapability
                switch terminal {
                case .failure:
                    passkey = RecordingPasskeyCapability(
                        assertionResult: .failure(.general("provider failed", cause)),
                        attestationResult: .failure(.general("provider failed", cause))
                    )
                case .canceled:
                    passkey = RecordingPasskeyCapability(
                        assertionResult: .canceled(reason),
                        attestationResult: .canceled(reason)
                    )
                }

                switch route {
                case .assertion:
                    let adapter = PasskeyAssertionUIImpl(
                        uiContextProvider: { FixedUIContextProvider(window: window) },
                        passkeyProvider: { passkey },
                        logger: nil
                    )
                    let result = await adapter.getCredential(options: testAssertionOptions())
                    expectPasskeyTerminal(result, terminal: terminal, cause: cause, reason: reason)
                case .attestation:
                    let adapter = PasskeyAttestationUIImpl(
                        uiContextProvider: { FixedUIContextProvider(window: window) },
                        passkeyProvider: { passkey },
                        logger: nil
                    )
                    let result = await adapter.createCredential(options: testAttestationOptions())
                    expectPasskeyTerminal(result, terminal: terminal, cause: cause, reason: reason)
                }
                #expect(passkey.receivedWindow === window)
            }
        }
    }

    @Test func `Passkey context failure returns the provider error and logs its cause`() async throws {
        let contextError = UIContextResolutionError(
            reason: .ownerClosed,
            message: "WebBridge owner closed",
            cause: AdapterTestError.contextUnavailable
        )
        let passkey = RecordingPasskeyCapability()
        let sink = LogCapture()
        let adapter = PasskeyAssertionUIImpl(
            uiContextProvider: { FixedUIContextProvider(failure: contextError) },
            passkeyProvider: { passkey },
            logger: testLogRouter(sink: sink)
        )

        let result = await adapter.getCredential(options: testAssertionOptions())

        guard case .failure(.general(let message, let cause, _)) = result else {
            Issue.record("Expected a general passkey failure")
            return
        }
        #expect(message == "Failed to resolve a presentation window: " + contextError.localizedDescription)
        #expect((cause as? UIContextResolutionError)?.reason == .ownerClosed)
        #expect(passkey.assertionCallCount == 0)
        let warning = try #require(sink.entries.first)
        #expect(warning.level == .warn)
        #expect(warning.message == "UI context resolution failed")
        #expect(warning.hasCause)
        #expect(warning.causeDescription == contextError.localizedDescription)
    }

    @Test func `Apple UI adapter forwards context and cancellation to the active provider`() async throws {
        let window = makeTestWindow()
        let provider = RecordingSocialProvider(waitsForCompletion: true)
        let adapter = SignInWithAppleUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            provider: { provider },
            logger: nil
        )

        let task = Task { @MainActor in
            await adapter.signIn(clientID: "apple-client", nonce: "apple-nonce")
        }
        await provider.waitForSignIn()

        #expect(provider.receivedWindow === window)
        #expect(provider.receivedParams?.clientID == "apple-client")
        #expect(provider.receivedParams?.nonce == "apple-nonce")

        adapter.cancel()
        #expect(provider.cancelCallCount == 1)
        provider.finish(.success(id: "apple-user", idToken: "apple-token"))

        let result = await task.value
        #expect(result.isSuccess)
    }

    @Test func `Apple UI adapter preserves provider success failure and cancellation exactly`() async throws {
        for terminal in SocialAdapterTerminal.allCases {
            let window = makeTestWindow()
            let cause = NSError(domain: "adapter.apple.test", code: 42)
            let reason = Reason.userClose(details: "Apple dismissed")
            let providerResult: SocialResult =
                switch terminal {
                case .success: .success(id: "apple-user", idToken: "apple-token")
                case .failure: .fail(error: .general("provider failed", cause))
                case .canceled: .canceled(reason: reason)
                }
            let provider = RecordingSocialProvider(result: providerResult)
            let adapter = SignInWithAppleUIImpl(
                uiContextProvider: { FixedUIContextProvider(window: window) },
                provider: { provider },
                logger: nil
            )

            let result = await adapter.signIn(clientID: "apple-client", nonce: "apple-nonce")

            switch (terminal, result) {
            case (.success, .success(let id, let idToken)):
                #expect(id == "apple-user")
                #expect(idToken == "apple-token")
            case (.failure, .fail(.general(let message, let actualCause))):
                #expect(message == "provider failed")
                #expect((actualCause as NSError?) === cause)
            case (.canceled, .canceled(let actualReason)):
                #expect(actualReason.description == reason.description)
            default:
                Issue.record("Expected Apple \(terminal) to pass through, got \(result)")
            }
            #expect(provider.receivedWindow === window)
            #expect(provider.receivedParams?.clientID == "apple-client")
            #expect(provider.receivedParams?.nonce == "apple-nonce")
            #expect(provider.signInCallCount == 1)
        }
    }

    @Test func `Google UI adapter forwards the resolved window and provider result`() async throws {
        let window = makeTestWindow()
        let provider = RecordingSocialProvider(result: .success(id: "google-user", idToken: "google-token"))
        let adapter = SignInWithGoogleUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            provider: { provider },
            logger: nil
        )

        let result = await adapter.signIn(clientID: "google-client", nonce: "google-nonce")

        #expect(result.isSuccess)
        #expect(provider.receivedWindow === window)
        #expect(provider.receivedParams?.clientID == "google-client")
        #expect(provider.receivedParams?.nonce == "google-nonce")
        #expect(provider.signInCallCount == 1)
    }

    @Test func `Google UI adapter preserves provider failures and cancellations exactly`() async throws {
        for terminal in AdapterTerminal.allCases {
            let window = makeTestWindow()
            let cause = NSError(domain: "adapter.google.test", code: 42)
            let reason = Reason.userClose(details: "Google dismissed")
            let providerResult: SocialResult =
                switch terminal {
                case .failure: .fail(error: .general("provider failed", cause))
                case .canceled: .canceled(reason: reason)
                }
            let provider = RecordingSocialProvider(result: providerResult)
            let adapter = SignInWithGoogleUIImpl(
                uiContextProvider: { FixedUIContextProvider(window: window) },
                provider: { provider },
                logger: nil
            )

            let result = await adapter.signIn(clientID: "google-client", nonce: "google-nonce")

            switch (terminal, result) {
            case (.failure, .fail(.general(let message, let actualCause))):
                #expect(message == "provider failed")
                #expect((actualCause as NSError?) === cause)
            case (.canceled, .canceled(let actualReason)):
                #expect(actualReason.description == reason.description)
            default:
                Issue.record("Expected \(terminal) to pass through, got \(result)")
            }
            #expect(provider.receivedWindow === window)
            #expect(provider.signInCallCount == 1)
        }
    }

    @Test func `Google UI adapter preserves provider cancellation`() async throws {
        let window = makeTestWindow()
        let provider = RecordingSocialProvider(waitsForCompletion: true)
        let adapter = SignInWithGoogleUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            provider: { provider },
            logger: nil
        )
        let task = Task { @MainActor in
            await adapter.signIn(clientID: "google-client", nonce: "google-nonce")
        }

        await provider.waitForSignIn()
        adapter.cancel()
        #expect(provider.cancelCallCount == 1)
        provider.finish(.canceled(reason: .userClose(details: "dismissed")))

        guard case .canceled(let reason) = await task.value else {
            Issue.record("Expected the provider cancellation to be preserved")
            return
        }
        #expect(reason.description == Reason.userClose(details: "dismissed").description)
    }

    @Test func `Google UI adapter cancels only the latest active request`() async throws {
        let window = makeTestWindow()
        let provider = RecordingSocialProvider(waitsForCompletion: true)
        let adapter = SignInWithGoogleUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            provider: { provider },
            logger: nil
        )
        let firstTask = Task { @MainActor in
            await adapter.signIn(clientID: "first-client", nonce: "first-nonce")
        }
        let secondTask = Task { @MainActor in
            await adapter.signIn(clientID: "second-client", nonce: "second-nonce")
        }

        await provider.waitForSignIns(2)
        adapter.cancel()
        #expect(provider.cancelCallCount == 1)
        provider.finishAll(.success(id: "google-user", idToken: "google-token"))

        #expect((await firstTask.value).isSuccess)
        #expect((await secondTask.value).isSuccess)
    }

    @Test func `Google UI adapter cancellation before invocation is a no-op`() async throws {
        let window = makeTestWindow()
        let provider = RecordingSocialProvider()
        let adapter = SignInWithGoogleUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            provider: { provider },
            logger: nil
        )

        adapter.cancel()
        let result = await adapter.signIn(clientID: "google-client", nonce: nil)

        #expect(result.isSuccess)
        #expect(provider.cancelCallCount == 0)
        #expect(provider.signInCallCount == 1)
    }

    @Test func `Google UI adapter cancellation after settlement is a no-op`() async throws {
        let window = makeTestWindow()
        let provider = RecordingSocialProvider()
        let adapter = SignInWithGoogleUIImpl(
            uiContextProvider: { FixedUIContextProvider(window: window) },
            provider: { provider },
            logger: nil
        )

        let result = await adapter.signIn(clientID: "google-client", nonce: nil)
        adapter.cancel()

        #expect(result.isSuccess)
        #expect(provider.cancelCallCount == 0)
    }

    @Test func `Google UI adapter skips provider and logs context failure`() async throws {
        let contextError = UIContextResolutionError(
            reason: .unavailable,
            message: "No foreground window",
            cause: AdapterTestError.contextUnavailable
        )
        let provider = RecordingSocialProvider(result: .success(id: "google-user", idToken: "google-token"))
        let sink = LogCapture()
        let adapter = SignInWithGoogleUIImpl(
            uiContextProvider: { FixedUIContextProvider(failure: contextError) },
            provider: { provider },
            logger: testLogRouter(sink: sink)
        )

        let result = await adapter.signIn(clientID: "google-client", nonce: nil)

        guard case .fail(.general(let message, _)) = result else {
            Issue.record("Expected a social context-resolution failure")
            return
        }
        #expect(message == "Failed to resolve a presentation window: " + contextError.localizedDescription)
        #expect(sink.entries.first?.level == .warn)
        #expect(sink.entries.first?.message == "UI context resolution failed")
        #expect(sink.entries.first?.causeDescription == contextError.localizedDescription)
        #expect(provider.signInCallCount == 0)
    }

    @Test func `Apple UI adapter logs context failure with the original reason and cause`() async throws {
        let contextError = UIContextResolutionError(
            reason: .unavailable,
            message: "No connected WebBridge window",
            cause: AdapterTestError.contextUnavailable
        )
        let provider = RecordingSocialProvider()
        let sink = LogCapture()
        let adapter = SignInWithAppleUIImpl(
            uiContextProvider: { FixedUIContextProvider(failure: contextError) },
            provider: { provider },
            logger: testLogRouter(sink: sink)
        )

        let result = await adapter.signIn(clientID: "apple-client", nonce: nil)

        guard case .fail(.general(let message, let cause)) = result else {
            Issue.record("Expected a social context-resolution failure")
            return
        }
        #expect(message == "Failed to resolve a presentation window: " + contextError.localizedDescription)
        #expect((cause as? UIContextResolutionError)?.reason == .unavailable)
        #expect(provider.signInCallCount == 0)
        let warning = try #require(sink.entries.first)
        #expect(warning.level == .warn)
        #expect(warning.message == "UI context resolution failed")
        #expect(warning.hasCause)
        #expect(warning.causeDescription == contextError.localizedDescription)
    }
}

private enum AdapterTestError: Error, Sendable {
    case contextUnavailable
}

private enum AdapterTerminal: String, CaseIterable, Sendable {
    case failure
    case canceled
}

private enum SocialAdapterTerminal: String, CaseIterable, Sendable {
    case success
    case failure
    case canceled
}

private enum PasskeyAdapterRoute: Int, CaseIterable, Sendable {
    case assertion = 1
    case attestation = 2
}

private func expectPasskeyTerminal<R: Sendable>(
    _ result: PasskeyResult<R>,
    terminal: AdapterTerminal,
    cause: NSError,
    reason: Reason,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    switch (terminal, result) {
    case (.failure, .failure(.general(let message, let actualCause, _))):
        #expect(message == "provider failed", sourceLocation: sourceLocation)
        #expect((actualCause as NSError?) === cause, sourceLocation: sourceLocation)
    case (.canceled, .canceled(let actualReason)):
        #expect(actualReason.description == reason.description, sourceLocation: sourceLocation)
    default:
        Issue.record("Expected \(terminal) to pass through, got \(result)", sourceLocation: sourceLocation)
    }
}

@MainActor
private func makeTestWindow() -> UIWindow {
    UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
}

private final class FixedUIContextProvider: UIContextProvider, @unchecked Sendable {
    private let result: UIContextResult

    init(window: UIWindow) {
        result = .windowOnly(window)
    }

    init(failure: any Error) {
        result = .failure(failure)
    }

    @MainActor func current() -> UIContextResult {
        result
    }
}

@MainActor
private final class RecordingPasskeyCapability: PasskeyProtocol, @unchecked Sendable {
    private let assertionResult: PasskeyResult<AssertionResult>
    private let attestationResult: PasskeyResult<AttestationResult>
    private(set) var receivedWindow: UIWindow?
    private(set) var receivedAssertionOptions: AssertionOptions?
    private(set) var receivedAttestationOptions: AttestationOptions?
    private(set) var assertionCallCount = 0
    private(set) var attestationCallCount = 0

    init(
        assertionResult: PasskeyResult<AssertionResult> = .success(testAssertionResult()),
        attestationResult: PasskeyResult<AttestationResult> = .success(testAttestationResult())
    ) {
        self.assertionResult = assertionResult
        self.attestationResult = attestationResult
    }

    func getCredential(window: UIWindow, assertionOptions: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        receivedWindow = window
        receivedAssertionOptions = assertionOptions
        assertionCallCount += 1
        return assertionResult
    }

    func createCredential(window: UIWindow, attestationOptions: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        receivedWindow = window
        receivedAttestationOptions = attestationOptions
        attestationCallCount += 1
        return attestationResult
    }
}

@MainActor
private final class RecordingSocialProvider: SignInWithApple, SignInWithGoogle, @unchecked Sendable {
    private let result: SocialResult
    private var continuations: [CheckedContinuation<SocialResult, Never>] = []
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var receivedWindow: UIWindow?
    private(set) var receivedParams: SignInWithSocialParams?
    private(set) var signInCallCount = 0
    private(set) var cancelCallCount = 0
    private var waitsForCompletion = false

    init(result: SocialResult = .success(id: "provider-user", idToken: "provider-token"), waitsForCompletion: Bool = false) {
        self.result = result
        self.waitsForCompletion = waitsForCompletion
    }

    func isAvailable(params: (any CapabilityParams)?) async -> Bool { true }

    func signIn(window: UIWindow, params: SignInWithSocialParams) async -> SocialResult {
        receivedWindow = window
        receivedParams = params
        signInCallCount += 1
        for waiter in startedWaiters { waiter.resume() }
        startedWaiters.removeAll()
        if waitsForCompletion {
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return result
    }

    func cancel() {
        cancelCallCount += 1
    }

    func signOut() {}

    func waitForSignIn() async {
        if signInCallCount > 0 { return }
        await withCheckedContinuation { continuation in
            if signInCallCount > 0 {
                continuation.resume()
            } else {
                startedWaiters.append(continuation)
            }
        }
    }

    func waitForSignIns(_ count: Int) async {
        while signInCallCount < count {
            await Task.yield()
        }
    }

    func finish(_ result: SocialResult) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: result)
    }

    func finishAll(_ result: SocialResult) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: result) }
    }
}

extension PasskeyResult {
    fileprivate var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

extension SocialResult {
    fileprivate var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
