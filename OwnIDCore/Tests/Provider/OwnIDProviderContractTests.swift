import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct OwnIDProviderContractTests {

    @Test func `Provider parameter value objects preserve inputs`() {
        let loginID = LoginID(id: "  person@example.com  ", type: .email)
        let accessToken = AccessToken(token: "access-token")

        let sessionParams = SessionCreateParams(
            loginID: loginID,
            accessToken: accessToken,
            authMethod: .password,
            sessionPayload: #"{"session":"payload"}"#
        )

        #expect(sessionParams.loginID == loginID)
        #expect(sessionParams.accessToken == accessToken)
        #expect(sessionParams.authMethod == .password)
        #expect(sessionParams.sessionPayload == #"{"session":"payload"}"#)

        let passwordParams = PasswordAuthenticateParams(loginID: loginID, password: "  raw password  ")

        #expect(passwordParams.loginID == loginID)
        #expect(passwordParams.password == "  raw password  ")

        let socialParams = SignInWithSocialParams(clientID: "client-id", nonce: "nonce", window: nil)

        #expect(socialParams.clientID == "client-id")
        #expect(socialParams.nonce == "nonce")
        #expect(socialParams.window == nil)

        let sessionOutput = SessionOutput(session: "host-session")
        let nilSessionOutput = SessionOutput(session: nil)

        #expect(sessionOutput.session as? String == "host-session")
        #expect(nilSessionOutput.session == nil)
    }

    @Test func `Session create builder uses default and typed availability and create handler`() async throws {
        let params = SessionCreateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            accessToken: AccessToken(token: "access-token"),
            authMethod: .passkey,
            sessionPayload: "payload"
        )
        var builder = SessionCreateBuilder()

        builder.isAvailable { params in
            params.loginID.id == "person@example.com" && params.authMethod == .passkey
        }
        builder.create { params in
            .success(SessionOutput(session: "created:\(params.sessionPayload)"))
        }

        let provider = builder.build()
        let nilAvailability = await provider.isAvailable(params: nil)
        let typedAvailability = await provider.isAvailable(params: params)
        let unsupportedAvailability = await provider.isAvailable(params: UnsupportedCapabilityParams())

        #expect(nilAvailability)
        #expect(typedAvailability)
        #expect(!(unsupportedAvailability))

        let output = try #require((await provider.create(params: params)).successValue)
        #expect(output.session as? String == "created:payload")
    }

    @Test func `Password authenticate builder uses default and typed availability and authenticate handler`() async throws {
        let params = PasswordAuthenticateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            password: "secret"
        )
        var builder = PasswordAuthenticateBuilder()

        builder.isAvailable { params in
            params.loginID.id == "person@example.com" && params.password == "secret"
        }
        builder.authenticate { params in
            .success(SessionOutput(session: "authenticated:\(params.loginID.id)"))
        }

        let provider = builder.build()
        let nilAvailability = await provider.isAvailable(params: nil)
        let typedAvailability = await provider.isAvailable(params: params)
        let unsupportedAvailability = await provider.isAvailable(params: UnsupportedCapabilityParams())

        #expect(nilAvailability)
        #expect(typedAvailability)
        #expect(!(unsupportedAvailability))

        let output = try #require((await provider.authenticate(params: params)).successValue)
        #expect(output.session as? String == "authenticated:person@example.com")
    }

    @Test func `Sign in with Google builder uses default and typed availability and handlers`() async throws {
        let params = SignInWithSocialParams(clientID: "google-client", nonce: "nonce", window: nil)
        let calls = LockedStrings()
        var builder = SignInWithGoogleBuilder()

        builder.isAvailable { params in
            params.clientID == "google-client" && params.nonce == "nonce"
        }
        builder.signIn { params in
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

        let signIn = try requireSocialSuccess(await provider.signIn(params: params))
        #expect(signIn.id == "google-id")
        #expect(signIn.idToken == "id-token")

        await provider.cancel()
        await provider.signOut()

        #expect(calls.values == ["signIn:google-client", "cancel", "signOut"])
    }

    @Test func `Provider builders forward failure and cancellation results`() async throws {
        let sessionParams = SessionCreateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            accessToken: AccessToken(token: "access-token"),
            authMethod: .passkey,
            sessionPayload: "payload"
        )
        var sessionBuilder = SessionCreateBuilder()
        sessionBuilder.create { _ in .failure(ProviderTestError("session-create")) }

        let sessionError = try #require((await sessionBuilder.build().create(params: sessionParams)).failureValue)
        #expect(sessionError as? ProviderTestError == ProviderTestError("session-create"))

        let passwordParams = PasswordAuthenticateParams(
            loginID: LoginID(id: "person@example.com", type: .email),
            password: "secret"
        )
        var passwordBuilder = PasswordAuthenticateBuilder()
        passwordBuilder.authenticate { _ in .failure(ProviderTestError("password-authenticate")) }

        let passwordError = try #require((await passwordBuilder.build().authenticate(params: passwordParams)).failureValue)
        #expect(passwordError as? ProviderTestError == ProviderTestError("password-authenticate"))

        let socialParams = SignInWithSocialParams(clientID: "google-client", nonce: "nonce", window: nil)
        var canceledGoogleBuilder = SignInWithGoogleBuilder()
        canceledGoogleBuilder.signIn { _ in .canceled(reason: .userClose(details: "dismissed")) }

        let cancellation = try requireSocialCancellation(await canceledGoogleBuilder.build().signIn(params: socialParams))
        #expect(cancellation.description == "userClose: dismissed")

        var failedGoogleBuilder = SignInWithGoogleBuilder()
        failedGoogleBuilder.signIn { _ in .fail(error: .general("google-provider-failed", ProviderTestError("google"))) }

        let googleError = try requireSocialFailure(await failedGoogleBuilder.build().signIn(params: socialParams))
        #expect(googleError.errorDescription == "google-provider-failed")
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
                builder.signIn { _ in .success(id: "google-id", idToken: "id-token") }
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

private struct ProviderTestError: Error, Equatable, Sendable {
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
