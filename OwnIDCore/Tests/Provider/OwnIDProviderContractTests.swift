import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: CFG-140, CFG-150, CFG-160, CFG-170, CFG-190, CFG-200, CFG-210, CFG-220, CFG-280
struct OwnIDProviderContractTests {

    @Test func `Session create builder uses default and typed availability and create handler`() async throws {
        let params = SessionCreateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            accessToken: AccessToken(token: "access-token"),
            authMethod: .passkey,
            sessionPayload: "payload"
        )
        let expectedOutput = SessionOutput(session: "created-session")
        var builder = SessionCreateBuilder()

        builder.isAvailable { params in
            #expect(params.loginID.id == "person@example.com")
            #expect(params.loginID.type == .email)
            #expect(params.accessToken == AccessToken(token: "access-token"))
            #expect(params.authMethod == .passkey)
            #expect(params.sessionPayload == "payload")
            return true
        }
        builder.create { params in
            #expect(params.loginID.id == "person@example.com")
            #expect(params.loginID.type == .email)
            #expect(params.accessToken == AccessToken(token: "access-token"))
            #expect(params.authMethod == .passkey)
            #expect(params.sessionPayload == "payload")
            return .success(expectedOutput)
        }

        let provider = builder.build()
        let nilAvailability = await provider.isAvailable(params: nil)
        let typedAvailability = await provider.isAvailable(params: params)
        let unsupportedAvailability = await provider.isAvailable(params: UnsupportedCapabilityParams())

        #expect(nilAvailability)
        #expect(typedAvailability)
        #expect(!(unsupportedAvailability))

        let output = try #require((await provider.create(params: params)).successValue)
        #expect(output === expectedOutput)
        #expect(output.session as? String == "created-session")

        let nilSessionOutput = SessionOutput(session: nil)
        var nilSessionBuilder = SessionCreateBuilder()
        nilSessionBuilder.create { _ in .success(nilSessionOutput) }

        let returnedNilSessionOutput = try #require((await nilSessionBuilder.build().create(params: params)).successValue)
        #expect(returnedNilSessionOutput === nilSessionOutput)
        #expect(returnedNilSessionOutput.session == nil)
    }

    @Test func `Password authenticate builder uses default and typed availability and authenticate handler`() async throws {
        let params = PasswordAuthenticateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            password: "secret"
        )
        let expectedOutput = SessionOutput(session: "authenticated-session")
        var builder = PasswordAuthenticateBuilder()

        builder.isAvailable { params in
            #expect(params.loginID.id == "person@example.com")
            #expect(params.loginID.type == .email)
            #expect(params.password == "secret")
            return true
        }
        builder.authenticate { params in
            #expect(params.loginID.id == "person@example.com")
            #expect(params.loginID.type == .email)
            #expect(params.password == "secret")
            return .success(expectedOutput)
        }

        let provider = builder.build()
        let nilAvailability = await provider.isAvailable(params: nil)
        let typedAvailability = await provider.isAvailable(params: params)
        let unsupportedAvailability = await provider.isAvailable(params: UnsupportedCapabilityParams())

        #expect(nilAvailability)
        #expect(typedAvailability)
        #expect(!(unsupportedAvailability))

        let output = try #require((await provider.authenticate(params: params)).successValue)
        #expect(output === expectedOutput)
        #expect(output.session as? String == "authenticated-session")
    }

    @Test @MainActor func `Sign in with Google builder uses default and typed availability and handlers`() async throws {
        let params = SignInWithSocialParams(clientID: "google-client", nonce: "nonce")
        let expectedWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let calls = LockedStrings()
        var builder = SignInWithGoogleBuilder()

        builder.isAvailable { params in
            params.clientID == "google-client" && params.nonce == "nonce"
        }
        builder.signIn { window, params in
            #expect(window === expectedWindow)
            calls.append("signIn:\(params.clientID)")
            return .success(id: "google-id", idToken: "id-token")
        }
        builder.cancel {
            calls.append("cancel")
        }
        builder.signOut {
            calls.append("signOut")
        }

        let provider = builder.build()
        let nilAvailability = await provider.isAvailable(params: nil)
        let typedAvailability = await provider.isAvailable(params: params)
        let unsupportedAvailability = await provider.isAvailable(params: UnsupportedCapabilityParams())

        #expect(nilAvailability)
        #expect(typedAvailability)
        #expect(!(unsupportedAvailability))

        let signIn = try requireSocialSuccess(await provider.signIn(window: expectedWindow, params: params))
        #expect(signIn.id == "google-id")
        #expect(signIn.idToken == "id-token")

        provider.cancel()
        provider.signOut()

        #expect(calls.values == ["signIn:google-client", "cancel", "signOut"])
    }

    @Test @MainActor func `Provider builders forward failure and cancellation results`() async throws {
        let sessionParams = SessionCreateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            accessToken: AccessToken(token: "access-token"),
            authMethod: .passkey,
            sessionPayload: "payload"
        )
        let sessionFailure = ProviderTestError("session-create")
        var sessionBuilder = SessionCreateBuilder()
        sessionBuilder.create { _ in .failure(sessionFailure) }

        let sessionError = try #require((await sessionBuilder.build().create(params: sessionParams)).failureValue)
        #expect(sessionError as? ProviderTestError === sessionFailure)

        let passwordParams = PasswordAuthenticateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            password: "secret"
        )
        let passwordFailure = ProviderTestError("password-authenticate")
        var passwordBuilder = PasswordAuthenticateBuilder()
        passwordBuilder.authenticate { _ in .failure(passwordFailure) }

        let passwordError = try #require((await passwordBuilder.build().authenticate(params: passwordParams)).failureValue)
        #expect(passwordError as? ProviderTestError === passwordFailure)

        let socialParams = SignInWithSocialParams(clientID: "google-client", nonce: "nonce")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var canceledGoogleBuilder = SignInWithGoogleBuilder()
        canceledGoogleBuilder.signIn { _, _ in .canceled(reason: .userClose(details: "dismissed")) }

        let cancellation = try requireSocialCancellation(
            await canceledGoogleBuilder.build().signIn(window: window, params: socialParams)
        )
        guard case .userClose(let details) = cancellation else {
            Issue.record("Expected user-close cancellation, got \(cancellation)")
            return
        }
        #expect(details == "dismissed")

        var failedGoogleBuilder = SignInWithGoogleBuilder()
        let googleFailure = ProviderTestError("google")
        failedGoogleBuilder.signIn { _, _ in .fail(error: .general("google-provider-failed", googleFailure)) }

        let googleError = try requireSocialFailure(
            await failedGoogleBuilder.build().signIn(window: window, params: socialParams)
        )
        guard case .general(let message, let underlyingError) = googleError else {
            Issue.record("Expected general provider failure, got \(googleError)")
            return
        }
        #expect(message == "google-provider-failed")
        #expect(underlyingError as? ProviderTestError === googleFailure)
    }

    @Test func `Core Apple capability and Google registrar preserve iOS provider asymmetry`() throws {
        let root = DIContainerImpl(scopeName: "provider-asymmetry")
        root.injectInstanceDefaults(
            instanceName: .default,
            configuration: try OwnIDConfigurationImpl(appID: "ABC123")
        )

        #expect(root.getOrNil(type: (any SignInWithApple).self) != nil)
        #expect(root.getOrNil(type: (any SignInWithGoogle).self) == nil)

        let child = root.withProviders("google-provider") { registrar in
            registrar.signInWithGoogle { builder in
                builder.signIn { _, _ in .success(id: "google-id", idToken: "id-token") }
            }
        }

        #expect(root.getOrNil(type: (any SignInWithGoogle).self) == nil)
        #expect(child.getOrNil(type: (any SignInWithApple).self) != nil)
        #expect(child.getOrNil(type: (any SignInWithGoogle).self) != nil)
    }

    @Test func `Provider registration no-op last-wins and scope mutation semantics`() async throws {
        let root = DIContainerImpl(scopeName: "root")

        let emptyChild = root.withProviders { _ in }

        #expect((emptyChild as? DIContainerImpl) === root)

        let returnedRoot = root.setProviders { registrar in
            registrar.sessionCreate { builder in
                builder.create { _ in .success(SessionOutput(session: "first")) }
            }
            registrar.sessionCreate { builder in
                builder.create { _ in .success(SessionOutput(session: "second")) }
            }
        }

        #expect(returnedRoot === root)
        let rootSession = try await awaitSession(root.getOrThrow(type: (any SessionCreate).self), payload: "root")

        #expect(rootSession == "second")

        let child = root.withProviders("child") { registrar in
            registrar.passwordAuthenticate { builder in
                builder.authenticate { _ in .success(SessionOutput(session: "child-password")) }
            }
        }

        #expect(root.getOrNil(type: (any PasswordAuthenticate).self) == nil)
        #expect(child.getOrNil(type: (any PasswordAuthenticate).self) != nil)
        let childSession = try await awaitSession(child.getOrThrow(type: (any SessionCreate).self), payload: "child")

        #expect(childSession == "second")
    }

    @Test func `Provider registrar lookup reads current scope before block registrations are applied`() throws {
        let root = DIContainerImpl(scopeName: "root")
        var sameBlockSessionVisible = true

        let returnedRoot = root.setProviders { registrar in
            registrar.sessionCreate { builder in
                builder.create { _ in .success(SessionOutput(session: "root-session")) }
            }
            sameBlockSessionVisible = registrar.getOrNil(type: (any SessionCreate).self) != nil
        }

        #expect(returnedRoot === root)
        #expect(!sameBlockSessionVisible)
        #expect(root.getOrNil(type: (any SessionCreate).self) != nil)

        var inheritedSessionVisible = false
        var sameBlockPasswordVisible = true
        let child = root.withProviders("child") { registrar in
            inheritedSessionVisible = registrar.getOrNil(type: (any SessionCreate).self) != nil
            registrar.passwordAuthenticate { builder in
                builder.authenticate { _ in .success(SessionOutput(session: "child-password")) }
            }
            sameBlockPasswordVisible = registrar.getOrNil(type: (any PasswordAuthenticate).self) != nil
        }

        #expect(inheritedSessionVisible)
        #expect(!sameBlockPasswordVisible)
        #expect(child.getOrNil(type: (any SessionCreate).self) != nil)
        #expect(child.getOrNil(type: (any PasswordAuthenticate).self) != nil)
        #expect(root.getOrNil(type: (any PasswordAuthenticate).self) == nil)
    }

    @Test @MainActor func `UI context provider registration is lazy and preserves the exact provider instance`() throws {
        let root = DIContainerImpl(scopeName: "ui-context-registration")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let provider = RecordingUIContextProvider(result: .windowOnly(window))

        let child = root.withProviders("child") { registrar in
            registrar.uiContext(provider)
        }

        #expect(provider.currentCallCount == 0)
        let resolved = try child.getOrThrow(type: (any UIContextProvider).self)
        let resolvedIsProvider = (resolved as AnyObject) === provider
        #expect(resolvedIsProvider)
        #expect(provider.currentCallCount == 0)

        let result = awaitCurrent(resolved)
        guard case .windowOnly(let resolvedWindow) = result else {
            Issue.record("Expected the registered provider result")
            return
        }
        #expect(resolvedWindow === window)
        #expect(provider.currentCallCount == 1)
    }

    @Test @MainActor func `UI context window overload resolves through its child scope`() throws {
        let root = DIContainerImpl(scopeName: "ui-context-owner-overloads")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        let windowScope = root.withProviders("window") { registrar in
            registrar.uiContext(window)
        }
        let windowProvider = try windowScope.getOrThrow(type: (any UIContextProvider).self)
        let windowResult = windowProvider.current()
        guard case .windowOnly(let resolvedWindow) = windowResult else {
            Issue.record("Expected the window overload to resolve the registered window")
            return
        }
        #expect(resolvedWindow === window)
    }

    @Test @MainActor func `UI context closure is not invoked during registration and resolves on demand`() throws {
        let root = DIContainerImpl(scopeName: "ui-context-closure")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let probe = UIContextClosureProbe(result: .windowOnly(window))

        let child = root.withProviders("child") { registrar in
            registrar.uiContext { @MainActor in
                probe.callCount += 1
                return probe.result
            }
        }

        #expect(probe.callCount == 0)
        let provider = try child.getOrThrow(type: (any UIContextProvider).self)
        #expect(probe.callCount == 0)
        _ = awaitCurrent(provider)
        #expect(probe.callCount == 1)
        _ = awaitCurrent(provider)
        #expect(probe.callCount == 2)
    }

    @Test @MainActor func `UI context scopes isolate overrides and set providers preserves omitted bindings`() throws {
        let root = DIContainerImpl(scopeName: "ui-context-scopes")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let parent = RecordingUIContextProvider(result: .windowOnly(window))
        let childOverride = RecordingUIContextProvider(result: .failure(UIContextResolutionError(reason: .unavailable, message: "child")))

        _ = root.setProviders { registrar in
            registrar.uiContext(parent)
            registrar.sessionCreate { builder in
                builder.create { _ in .success(SessionOutput(session: "preserved")) }
            }
        }

        let returnedRoot = root.setProviders { registrar in
            registrar.passwordAuthenticate { builder in
                builder.authenticate { _ in .success(SessionOutput(session: "later update")) }
            }
        }
        #expect(returnedRoot === root)

        let child = root.withProviders("child") { registrar in
            registrar.uiContext(childOverride)
        }

        let rootProvider = try root.getOrThrow(type: (any UIContextProvider).self)
        let childProvider = try child.getOrThrow(type: (any UIContextProvider).self)
        let rootUsesParentProvider = (rootProvider as AnyObject) === parent
        let childUsesOverrideProvider = (childProvider as AnyObject) === childOverride
        #expect(rootUsesParentProvider)
        #expect(childUsesOverrideProvider)
        #expect(child.getOrNil(type: (any SessionCreate).self) != nil)
        #expect(root.getOrNil(type: (any SessionCreate).self) != nil)
        #expect(root.getOrNil(type: (any PasswordAuthenticate).self) != nil)

        let rootResult = awaitCurrent(rootProvider)
        guard case .windowOnly(let resolvedWindow) = rootResult else {
            Issue.record("Expected the parent UI context to remain unchanged")
            return
        }
        #expect(resolvedWindow === window)
        guard case .failure(let error) = awaitCurrent(childProvider) else {
            Issue.record("Expected the child UI context override to remain authoritative")
            return
        }
        #expect((error as? UIContextResolutionError)?.message == "child")
    }

    @Test @MainActor func `UI context registration uses the last provider in one block`() throws {
        let root = DIContainerImpl(scopeName: "ui-context-last-wins")
        let first = RecordingUIContextProvider(result: .failure(UIContextResolutionError(reason: .unavailable, message: "first")))
        let second = RecordingUIContextProvider(result: .failure(UIContextResolutionError(reason: .unavailable, message: "second")))

        _ = root.setProviders { registrar in
            registrar.uiContext(first)
            registrar.uiContext(second)
        }

        let resolved = try root.getOrThrow(type: (any UIContextProvider).self)
        let resolvedIsLastProvider = (resolved as AnyObject) === second
        #expect(resolvedIsLastProvider)
    }

    @MainActor
    private func awaitCurrent(_ provider: any UIContextProvider) -> UIContextResult {
        provider.current()
    }

    private func awaitSession(_ provider: any SessionCreate, payload: String) async throws -> String? {
        let result = await provider.create(
            params: SessionCreateParams(
                loginID: LoginID(id: "person@example.com", type: .email),
                accessToken: AccessToken(token: "access-token"),
                authMethod: .password,
                sessionPayload: payload
            )
        )

        switch result {
        case .success(let output):
            return output.session as? String
        case .failure(let error):
            throw error
        }
    }

}

private struct UnsupportedCapabilityParams: CapabilityParams {}

private final class ProviderTestError: Error, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

extension Result {
    fileprivate var successValue: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    fileprivate var failureValue: Failure? {
        guard case .failure(let value) = self else { return nil }
        return value
    }
}

private func requireSocialSuccess(
    _ result: SocialResult,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (id: String, idToken: String) {
    guard case .success(let id, let idToken) = result else {
        return try #require(
            nil as (id: String, idToken: String)?,
            "Expected successful Google sign-in, got \(result)",
            sourceLocation: sourceLocation
        )
    }

    return (id, idToken)
}

private func requireSocialCancellation(
    _ result: SocialResult,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Reason {
    guard case .canceled(let reason) = result else {
        return try #require(
            nil as Reason?,
            "Expected Google cancellation, got \(result)",
            sourceLocation: sourceLocation
        )
    }

    return reason
}

private func requireSocialFailure(
    _ result: SocialResult,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> SocialResult.Error {
    guard case .fail(let error) = result else {
        return try #require(
            nil as SocialResult.Error?,
            "Expected Google failure, got \(result)",
            sourceLocation: sourceLocation
        )
    }

    return error
}

private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

@MainActor
private final class RecordingUIContextProvider: UIContextProvider, @unchecked Sendable {
    let result: UIContextResult
    private(set) var currentCallCount = 0

    init(result: UIContextResult) {
        self.result = result
    }

    func current() -> UIContextResult {
        currentCallCount += 1
        return result
    }
}

@MainActor
private final class UIContextClosureProbe: @unchecked Sendable {
    let result: UIContextResult
    var callCount = 0

    init(result: UIContextResult) {
        self.result = result
    }
}
