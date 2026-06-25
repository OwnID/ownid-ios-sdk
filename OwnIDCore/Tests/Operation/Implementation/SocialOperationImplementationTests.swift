import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct SocialOperationImplementationTests {

    @Test(arguments: SocialOperationCase.allCases)
    func `Social success completes OIDC challenge`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialSuccess(testCase)

        #expect(observation.response.accessToken == testAccessToken("\(testCase.key)-access-token"))
        #expect(observation.response.provider == testCase.provider)
        #expect(observation.idTokens == ["\(testCase.key)-id-token"])
        #expect(observation.receivedClientID == "\(testCase.key)-client-id")
        #expect(observation.receivedNonce == "\(testCase.key)-challenge")
        #expect(observation.apiParams.count == 1)
        #expect(observation.apiParams.first??.provider == testCase.provider)
        #expect(observation.apiParams.first??.accessToken == testCase.inputAccessToken)
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social cancellation cancels OIDC challenge`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialCancellation(testCase)

        #expect(observation.reason.description == Reason.userClose(details: "\(testCase.displayName) dismissed").description)
        #expect(observation.idTokens.isEmpty)
        #expect(observation.cancelReasons.map(\.description) == [observation.reason.description])
    }

    @Test(arguments: SocialOperationCase.allCases)
    func `Social provider failure becomes terminal integration failure`(_ testCase: SocialOperationCase) async throws {
        let observation = try await runSocialProviderFailure(testCase)

        #expect(observation.failure.errorCode == .oidcFailed)
        #expect(observation.failure.message == "general(\"\(testCase.displayName) provider failed\", nil)")
        #expect(observation.cancelReasons.count == 1)
    }

    private func runSocialSuccess(_ testCase: SocialOperationCase) async throws -> SocialSuccessObservation {
        let socialResult = SocialResult.success(id: "\(testCase.key)-user", idToken: "\(testCase.key)-id-token")
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider, challenge: "\(testCase.key)-challenge"),
            completeResult: .success(testSocialToken(provider: testCase.provider, token: "\(testCase.key)-access-token"))
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social success") {
                await operation.operation.start(params: SignInWithAppleOperationParams(accessToken: testCase.inputAccessToken))
                    .whenSettled()
            }
            return SocialSuccessObservation(
                response: try requireOperationSuccess(result),
                idTokens: apiController.idTokens.get(),
                apiParams: operation.api.params.get(),
                receivedClientID: await ui.receivedClientID,
                receivedNonce: await ui.receivedNonce
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social success") {
                await operation.operation.start(params: SignInWithGoogleOperationParams(accessToken: testCase.inputAccessToken))
                    .whenSettled()
            }
            return SocialSuccessObservation(
                response: try requireOperationSuccess(result),
                idTokens: apiController.idTokens.get(),
                apiParams: operation.api.params.get(),
                receivedClientID: await ui.receivedClientID,
                receivedNonce: await ui.receivedNonce
            )
        }
    }

    private func runSocialCancellation(_ testCase: SocialOperationCase) async throws -> SocialCancellationObservation {
        let socialResult = SocialResult.canceled(reason: .userClose(details: "\(testCase.displayName) dismissed"))
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider),
            completeResult: .success(testSocialToken(provider: testCase.provider))
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social cancellation") {
                await operation.operation.start(params: SignInWithAppleOperationParams()).whenSettled()
            }
            return SocialCancellationObservation(
                reason: try requireOperationCancellation(result),
                idTokens: apiController.idTokens.get(),
                cancelReasons: apiController.cancelReasons.get()
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social cancellation") {
                await operation.operation.start(params: SignInWithGoogleOperationParams()).whenSettled()
            }
            return SocialCancellationObservation(
                reason: try requireOperationCancellation(result),
                idTokens: apiController.idTokens.get(),
                cancelReasons: apiController.cancelReasons.get()
            )
        }
    }

    private func runSocialProviderFailure(_ testCase: SocialOperationCase) async throws -> SocialFailureObservation {
        let socialResult = SocialResult.fail(error: .general("\(testCase.displayName) provider failed"))
        let apiController = FakeOIDCAPIController(
            challenge: testSocialChallenge(provider: testCase.provider),
            completeResult: .success(testSocialToken(provider: testCase.provider))
        )

        switch testCase.provider {
        case .apple:
            let ui = await FakeAppleSignInUI(result: socialResult)
            let operation = makeAppleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social failure") {
                await operation.operation.start(params: SignInWithAppleOperationParams()).whenSettled()
            }
            return SocialFailureObservation(
                failure: try requireOperationFailure(result),
                cancelReasons: apiController.cancelReasons.get()
            )

        case .google:
            let ui = await FakeGoogleSignInUI(result: socialResult)
            let operation = makeGoogleOperation(ui: ui, apiController: apiController)
            let result = try await withOperationTimeout("\(testCase.displayName) social failure") {
                await operation.operation.start(params: SignInWithGoogleOperationParams()).whenSettled()
            }
            return SocialFailureObservation(
                failure: try requireOperationFailure(result),
                cancelReasons: apiController.cancelReasons.get()
            )
        }
    }

    private func makeAppleOperation(
        ui: FakeAppleSignInUI,
        apiController: FakeOIDCAPIController
    ) -> SocialOperationHarness<SignInWithAppleOperationImpl> {
        let api = FakeOIDCAPI(controller: apiController)
        return SocialOperationHarness(
            operation: SignInWithAppleOperationImpl(
                operationType: .oidcAuthenticationApple,
                operationRegistry: OperationRegistryImpl(logger: nil),
                ui: ui,
                api: api,
                taskScope: testTaskScope(),
                context: nil,
                logger: nil
            ),
            api: api
        )
    }

    private func makeGoogleOperation(
        ui: FakeGoogleSignInUI,
        apiController: FakeOIDCAPIController
    ) -> SocialOperationHarness<SignInWithGoogleOperationImpl> {
        let api = FakeOIDCAPI(controller: apiController)
        return SocialOperationHarness(
            operation: SignInWithGoogleOperationImpl(
                operationType: .oidcAuthenticationGoogle,
                operationRegistry: OperationRegistryImpl(logger: nil),
                ui: ui,
                api: api,
                taskScope: testTaskScope(),
                context: nil,
                logger: nil
            ),
            api: api
        )
    }
}

struct SocialOperationCase: Sendable, CustomTestStringConvertible {
    static let allCases = [
        SocialOperationCase(provider: .apple, displayName: "Apple", inputAccessToken: testAccessToken("session-access")),
        SocialOperationCase(provider: .google, displayName: "Google", inputAccessToken: nil),
    ]

    let provider: SocialProviderID
    let displayName: String
    let inputAccessToken: AccessToken?

    var key: String { provider.rawValue.lowercased() }
    var testDescription: String { displayName }
}

private struct SocialOperationHarness<Operation: Sendable>: Sendable {
    let operation: Operation
    let api: FakeOIDCAPI
}

private struct SocialSuccessObservation: Sendable {
    let response: AccessTokenWithUserInfo
    let idTokens: [String]
    let apiParams: [OIDCAPIParams?]
    let receivedClientID: String?
    let receivedNonce: String?
}

private struct SocialCancellationObservation: Sendable {
    let reason: Reason
    let idTokens: [String]
    let cancelReasons: [Reason]
}

private struct SocialFailureObservation: Sendable {
    let failure: any OperationFailure
    let cancelReasons: [Reason]
}
