import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: PROVIDER-CALLBACK-020
struct ProviderMainActorBoundaryTests {

    @Test func `Session and password provider hooks execute on MainActor when called from detached tasks`() async throws {
        let log = await MainActor.run { MainActorProviderEventLog() }
        let sessionParams = SessionCreateParams(
            loginID: LoginID(id: "session@example.com", type: .email),
            accessToken: AccessToken(token: "session-access-token"),
            authMethod: .passkey,
            sessionPayload: "session-payload"
        )
        let passwordParams = PasswordAuthenticateParams(
            loginID: LoginID(id: "password@example.com", type: .email),
            password: "secret"
        )
        var sessionBuilder = SessionCreateBuilder()
        sessionBuilder.isAvailable { params in
            log.append(.sessionAvailability(params.loginID.id))
            return true
        }
        sessionBuilder.create { params in
            log.append(.sessionCreate(params.sessionPayload))
            return .success(SessionOutput(session: "session:\(params.sessionPayload)"))
        }
        var passwordBuilder = PasswordAuthenticateBuilder()
        passwordBuilder.isAvailable { params in
            log.append(.passwordAvailability(params.loginID.id))
            return true
        }
        passwordBuilder.authenticate { params in
            log.append(.passwordAuthenticate(params.password))
            return .success(SessionOutput(session: "password:\(params.loginID.id)"))
        }

        let session = sessionBuilder.build()
        let password = passwordBuilder.build()
        let observation = try await Task.detached {
            let sessionAvailable = await session.isAvailable(params: sessionParams)
            let sessionOutput = try requireSessionString(await session.create(params: sessionParams))
            let passwordAvailable = await password.isAvailable(params: passwordParams)
            let passwordOutput = try requireSessionString(await password.authenticate(params: passwordParams))
            return ProviderSessionPasswordObservation(
                sessionAvailable: sessionAvailable,
                sessionOutput: sessionOutput,
                passwordAvailable: passwordAvailable,
                passwordOutput: passwordOutput
            )
        }.value

        #expect(observation.sessionAvailable)
        #expect(observation.sessionOutput == "session:session-payload")
        #expect(observation.passwordAvailable)
        #expect(observation.passwordOutput == "password:password@example.com")
        #expect(
            await log.snapshot() == [
                .sessionAvailability("session@example.com"),
                .sessionCreate("session-payload"),
                .passwordAvailability("password@example.com"),
                .passwordAuthenticate("secret"),
            ]
        )
    }

    @Test func `Google provider main actor hooks execute on MainActor when called from detached tasks`() async throws {
        let log = await MainActor.run { MainActorProviderEventLog() }
        let window = await MainActor.run { makeTestWindow() }
        let params = SocialSignInParams(clientID: "google-client", nonce: "google-nonce")
        var builder = GoogleSignInProviderBuilder()
        builder.signIn { _, params in
            log.append(.googleSignIn(params.clientID, params.nonce))
            return .success(id: "google-id", idToken: "google-id-token")
        }
        builder.cancel {
            log.append(.googleCancel)
        }
        builder.signOut {
            log.append(.googleSignOut)
        }

        let provider = builder.build()
        let result = await Task.detached {
            let result = await provider.signIn(window: window, params: params)
            await provider.cancel()
            await provider.signOut()
            return result
        }.value

        let success = try requireSocialSuccess(result)
        #expect(success.id == "google-id")
        #expect(success.idToken == "google-id-token")
        #expect(
            await log.snapshot() == [
                .googleSignIn("google-client", "google-nonce"),
                .googleCancel,
                .googleSignOut,
            ]
        )
    }

    @Test func `Apple provider and social UI wrappers invoke fake providers on MainActor without provider UI`() async throws {
        let log = await MainActor.run { MainActorProviderEventLog() }
        let appleProvider = FakeMainActorAppleProvider(log: log)
        let googleProvider = FakeMainActorGoogleProvider(log: log)
        let window = await MainActor.run { makeTestWindow() }
        let contextProvider = await MainActor.run {
            MainActorWindowContextProvider(window: window)
        }
        let appleUI = SignInWithAppleUIImpl(
            uiContextProvider: { contextProvider },
            provider: { appleProvider },
            logger: nil
        )
        let googleUI = SignInWithGoogleUIImpl(
            uiContextProvider: { contextProvider },
            provider: { googleProvider },
            logger: nil
        )

        let observation = await Task.detached {
            let appleProviderResult = await appleProvider.signIn(
                window: window,
                params: SocialSignInParams(clientID: "direct-apple-client", nonce: "direct-apple-nonce")
            )
            await appleProvider.cancel()
            let appleUIResult = await appleUI.signIn(clientID: "apple-client", nonce: "apple-nonce")
            let googleUIResult = await googleUI.signIn(clientID: "google-client", nonce: "google-nonce")
            return [appleProviderResult, appleUIResult, googleUIResult]
        }.value

        let appleProviderSuccess = try requireSocialSuccess(observation[0])
        let appleUISuccess = try requireSocialSuccess(observation[1])
        let googleUISuccess = try requireSocialSuccess(observation[2])

        #expect(appleProviderSuccess.id == "apple-id")
        #expect(appleProviderSuccess.idToken == "apple-token")
        #expect(appleUISuccess.id == "apple-id")
        #expect(appleUISuccess.idToken == "apple-token")
        #expect(googleUISuccess.id == "google-id")
        #expect(googleUISuccess.idToken == "google-token")
        #expect(await MainActor.run { appleProvider.receivedWindow === window })
        #expect(await MainActor.run { googleProvider.receivedWindow === window })
        #expect(
            await log.snapshot() == [
                .appleSignIn("direct-apple-client", "direct-apple-nonce"),
                .appleCancel,
                .appleSignIn("apple-client", "apple-nonce"),
                .googleSignIn("google-client", "google-nonce"),
            ]
        )
    }
}

private struct ProviderSessionPasswordObservation: Sendable {
    let sessionAvailable: Bool
    let sessionOutput: String?
    let passwordAvailable: Bool
    let passwordOutput: String?
}

private enum ProviderBoundaryTestError: Error, Sendable {
    case providerFailed(String)
    case socialCanceled(String)
}

private enum MainActorProviderEvent: Equatable, Sendable {
    case sessionAvailability(String)
    case sessionCreate(String)
    case passwordAvailability(String)
    case passwordAuthenticate(String)
    case appleSignIn(String, String?)
    case appleCancel
    case googleSignIn(String, String?)
    case googleCancel
    case googleSignOut
}

@MainActor
private final class MainActorProviderEventLog {
    private var events: [MainActorProviderEvent] = []

    func append(_ event: MainActorProviderEvent) {
        events.append(event)
    }

    func snapshot() -> [MainActorProviderEvent] {
        events
    }
}

private final class FakeMainActorAppleProvider: AppleSignInProvider, @unchecked Sendable {
    private let log: MainActorProviderEventLog
    private(set) var receivedWindow: UIWindow?

    init(log: MainActorProviderEventLog) {
        self.log = log
    }

    @MainActor func signIn(window: UIWindow, params: SocialSignInParams) async -> SocialSignInResult {
        receivedWindow = window
        log.append(.appleSignIn(params.clientID, params.nonce))
        return .success(id: "apple-id", idToken: "apple-token")
    }

    @MainActor func cancel() {
        log.append(.appleCancel)
    }
}

private final class FakeMainActorGoogleProvider: GoogleSignInProvider, @unchecked Sendable {
    private let log: MainActorProviderEventLog
    private(set) var receivedWindow: UIWindow?

    init(log: MainActorProviderEventLog) {
        self.log = log
    }

    @MainActor func signIn(window: UIWindow, params: SocialSignInParams) async -> SocialSignInResult {
        receivedWindow = window
        log.append(.googleSignIn(params.clientID, params.nonce))
        return .success(id: "google-id", idToken: "google-token")
    }

    @MainActor func cancel() {
        log.append(.googleCancel)
    }

    @MainActor func signOut() {
        log.append(.googleSignOut)
    }
}

@MainActor
private func makeTestWindow() -> UIWindow {
    UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
}

@MainActor
private final class MainActorWindowContextProvider: UIContextProvider, @unchecked Sendable {
    let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func current() -> UIContextResult {
        .windowOnly(window)
    }
}

private func requireSessionString(_ result: Result<SessionOutput, any Error & Sendable>) throws -> String? {
    switch result {
    case .success(let output):
        return output.session as? String
    case .failure(let error):
        throw ProviderBoundaryTestError.providerFailed(error.localizedDescription)
    }
}

private func requireSocialSuccess(_ result: SocialSignInResult) throws -> (id: String, idToken: String) {
    switch result {
    case .success(let id, let idToken):
        return (id, idToken)
    case .canceled(let reason):
        throw ProviderBoundaryTestError.socialCanceled(reason.description)
    case .fail(let error):
        throw ProviderBoundaryTestError.providerFailed(error.localizedDescription)
    }
}
