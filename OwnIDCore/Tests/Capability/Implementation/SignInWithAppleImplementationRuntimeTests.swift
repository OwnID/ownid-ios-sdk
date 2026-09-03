import AuthenticationServices
import Foundation
import Testing
import UIKit

@testable import OwnIDCore

// Covers: PROVIDER-RUNTIME-030
// The recording controller covers OwnID request and result handling after AuthenticationServices adaptation.
// Real ASAuthorization credential delivery, provider UI, and the private adapter's framework forwarding remain platform boundaries.
@MainActor
struct SignInWithAppleImplementationRuntimeTests {

    @Test func `Request forwards nonce, email scope and generated state`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(
                params: SignInWithSocialParams(clientID: "client-id", nonce: "server-nonce", window: nil)
            )
        }
        let controller = try await factory.waitForController()

        #expect(controller.request.nonce == "server-nonce")
        #expect(controller.request.requestedScopes == [.email])
        let state = try #require(controller.request.state)
        #expect(state.decodeBase64UrlSafe()?.count == 32)
        #expect(controller.performCallCount == 1)
        #expect(controller.presentationContextProvider === signIn)

        controller.complete(
            with: SignInWithAppleAuthorization(
                user: "apple-user",
                state: state,
                identityToken: Data("id-token".utf8)
            )
        )
        _ = try requireSuccess(await task.value)
    }

    @Test func `Matching authorization maps user and UTF8 identity token`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()
        let state = try #require(controller.request.state)

        controller.complete(
            with: SignInWithAppleAuthorization(
                user: "apple-user",
                state: state,
                identityToken: Data("токен".utf8)
            )
        )

        let success = try requireSuccess(await task.value)
        #expect(success.id == "apple-user")
        #expect(success.idToken == "токен")
    }

    @Test func `Mismatched authorization state fails before accepting token`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()

        controller.complete(
            with: SignInWithAppleAuthorization(
                user: "apple-user",
                state: "unexpected-state",
                identityToken: Data("id-token".utf8)
            )
        )

        try expectFailure(await task.value, message: "Apple authorization response state mismatch")
    }

    @Test(arguments: [
        SignInWithAppleAuthorization?(nil),
        SignInWithAppleAuthorization(user: "apple-user", state: "state", identityToken: nil),
    ])
    func `Missing authorization data fails without success`(_ authorization: SignInWithAppleAuthorization?) async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()

        controller.complete(with: authorization)

        try expectFailure(await task.value, message: "Data missing")
    }

    @Test func `Explicit cancel maps callback to authorization canceled`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()

        signIn.cancel()
        if #available(iOS 16.0, *) {
            #expect(controller.cancelCallCount == 1)
        } else {
            #expect(controller.cancelCallCount == 0)
        }
        controller.complete(with: ASAuthorizationError(.failed))

        let reason = try requireCancellation(await task.value)
        #expect(reason.description == Reason.userClose(details: "Authorization canceled").description)
    }

    @Test func `Provider cancel error maps to user-close cancellation`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()

        controller.complete(with: ASAuthorizationError(.canceled))

        let reason = try requireCancellation(await task.value)
        #expect(reason.description == Reason.userClose(details: "User canceled authorization").description)
    }

    @Test func `Provider authorization error maps to failure`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()

        controller.complete(with: ASAuthorizationError(.failed))

        try expectFailure(await task.value, message: "ASAuthorizationError")
    }

    @Test func `Non-authorization provider error maps to generic failure`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()

        controller.complete(with: AppleAuthorizationTestError.failed)

        try expectFailure(await task.value, message: "Error")
    }

    @Test func `Restart cancels prior request and ignores its late callback`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let signIn = makeSignIn(factory: factory)
        let firstTask = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: "first", window: nil))
        }
        let firstController = try await factory.waitForController()

        let secondTask = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: "second", window: nil))
        }
        let secondController = try await factory.waitForController(at: 1)

        let firstResult = await firstTask.value
        let firstReason = try requireCancellation(firstResult)
        #expect(firstReason.description == Reason.userClose(details: "Authorization restarted").description)
        if #available(iOS 16.0, *) {
            #expect(firstController.cancelCallCount == 1)
        } else {
            #expect(firstController.cancelCallCount == 0)
        }

        let firstState = try #require(firstController.request.state)
        firstController.complete(
            with: SignInWithAppleAuthorization(
                user: "stale-user",
                state: firstState,
                identityToken: Data("stale-token".utf8)
            )
        )

        let secondState = try #require(secondController.request.state)
        secondController.complete(
            with: SignInWithAppleAuthorization(
                user: "current-user",
                state: secondState,
                identityToken: Data("current-token".utf8)
            )
        )
        let secondSuccess = try requireSuccess(await secondTask.value)
        #expect(secondSuccess.id == "current-user")
        #expect(secondSuccess.idToken == "current-token")
    }

    @Test func `Presentation anchor prefers explicit window`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let expectedWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let signIn = makeSignIn(factory: factory)
        let task = Task {
            await signIn.signIn(
                params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: expectedWindow)
            )
        }
        let controller = try await factory.waitForController()
        let callbackController = ASAuthorizationController(authorizationRequests: [controller.request])

        #expect(signIn.presentationAnchor(for: callbackController) === expectedWindow)
        controller.complete(with: ASAuthorizationError(.canceled))
        _ = await task.value
    }

    @Test func `Presentation anchor falls back to active context window`() async throws {
        let factory = RecordingAppleAuthorizationControllerFactory()
        let expectedWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let contextProvider = FixedWindowUIContextProvider(activeWindow: expectedWindow)
        let signIn = makeSignIn(factory: factory, uiContextProvider: contextProvider)
        let task = Task {
            await signIn.signIn(params: SignInWithSocialParams(clientID: "client-id", nonce: nil, window: nil))
        }
        let controller = try await factory.waitForController()
        let callbackController = ASAuthorizationController(authorizationRequests: [controller.request])

        #expect(signIn.presentationAnchor(for: callbackController) === expectedWindow)
        #expect(contextProvider.activeWindowCallCount == 1)
        controller.complete(with: ASAuthorizationError(.canceled))
        _ = await task.value
    }
}

@MainActor
private func makeSignIn(
    factory: RecordingAppleAuthorizationControllerFactory,
    uiContextProvider: any UIContextProvider = FixedWindowUIContextProvider(activeWindow: nil)
) -> SignInWithAppleImpl {
    SignInWithAppleImpl(
        uiContextProvider: uiContextProvider,
        logger: nil,
        authorizationControllerFactory: { factory.makeController(request: $0) }
    )
}

private func requireSuccess(
    _ result: SocialResult,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> (id: String, idToken: String) {
    switch result {
    case .success(let id, let idToken): return (id, idToken)
    case .canceled(let reason):
        return try #require(nil as (String, String)?, "Expected success, got cancellation: \(reason)", sourceLocation: sourceLocation)
    case .fail(let error):
        return try #require(nil as (String, String)?, "Expected success, got failure: \(error)", sourceLocation: sourceLocation)
    }
}

private func requireCancellation(
    _ result: SocialResult,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Reason {
    switch result {
    case .canceled(let reason): return reason
    case .success(let id, let idToken):
        return try #require(nil as Reason?, "Expected cancellation, got success: \(id)/\(idToken)", sourceLocation: sourceLocation)
    case .fail(let error):
        return try #require(nil as Reason?, "Expected cancellation, got failure: \(error)", sourceLocation: sourceLocation)
    }
}

private func expectFailure(
    _ result: SocialResult,
    message: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    guard case .fail(let error) = result else {
        _ = try #require(nil as SocialResult.Error?, "Expected failure, got \(result)", sourceLocation: sourceLocation)
        return
    }
    guard case .general(let actualMessage, _) = error else {
        _ = try #require(nil as SocialResult.Error?, "Expected general failure, got \(error)", sourceLocation: sourceLocation)
        return
    }
    #expect(actualMessage == message, sourceLocation: sourceLocation)
}

@MainActor
private final class RecordingAppleAuthorizationControllerFactory {
    private(set) var controllers: [RecordingAppleAuthorizationController] = []
    private var controllerWaiters: [Int: [CheckedContinuation<RecordingAppleAuthorizationController, Never>]] = [:]

    func makeController(request: ASAuthorizationAppleIDRequest) -> any SignInWithAppleAuthorizationController {
        let controller = RecordingAppleAuthorizationController(request: request)
        controllers.append(controller)
        for (index, waiters) in controllerWaiters where controllers.indices.contains(index) {
            controllerWaiters.removeValue(forKey: index)
            for waiter in waiters { waiter.resume(returning: controllers[index]) }
        }
        return controller
    }

    func waitForController(at index: Int = 0) async throws -> RecordingAppleAuthorizationController {
        try await withTestTimeout("Apple authorization controller", seconds: 2) {
            await self.controller(at: index)
        }
    }

    private func controller(at index: Int) async -> RecordingAppleAuthorizationController {
        if controllers.indices.contains(index) { return controllers[index] }
        return await withCheckedContinuation { continuation in
            if controllers.indices.contains(index) {
                continuation.resume(returning: controllers[index])
            } else {
                controllerWaiters[index, default: []].append(continuation)
            }
        }
    }
}

@MainActor
private final class RecordingAppleAuthorizationController: SignInWithAppleAuthorizationController {
    let request: ASAuthorizationAppleIDRequest
    weak var delegate: (any SignInWithAppleAuthorizationControllerDelegate)?
    weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?
    private(set) var performCallCount = 0
    private(set) var cancelCallCount = 0

    init(request: ASAuthorizationAppleIDRequest) {
        self.request = request
    }

    func performRequests() {
        performCallCount += 1
    }

    func cancel() {
        cancelCallCount += 1
    }

    func complete(with authorization: SignInWithAppleAuthorization?) {
        delegate?.authorizationController(self, didCompleteWithAuthorization: authorization)
    }

    func complete(with error: any Error) {
        delegate?.authorizationController(self, didCompleteWithError: error)
    }
}

@MainActor
private final class FixedWindowUIContextProvider: UIContextProvider, @unchecked Sendable {
    private let window: UIWindow?
    private(set) var activeWindowCallCount = 0

    init(activeWindow: UIWindow?) {
        window = activeWindow
    }

    func activeWindow() -> UIWindow? {
        activeWindowCallCount += 1
        return window
    }

    func topMostViewController(_ window: UIWindow?) -> UIViewController? {
        window?.rootViewController
    }
}

private enum AppleAuthorizationTestError: Error {
    case failed
}
