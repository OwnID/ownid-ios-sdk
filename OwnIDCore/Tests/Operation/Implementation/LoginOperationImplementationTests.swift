import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct LoginOperationImplementationTests {

    @Test func `Login uses token API first and maps success terminal result`() async throws {
        let loginAPI = FakeLoginAPI(result: .success(testLoginResponse("token-route-access")))
        let discoverAPI = FakeDiscoverAPI(
            result: .failure(.unexpected(errorCode: .unknown, message: "unused", underlyingError: TestError()))
        )
        let operation = makeLoginOperation(loginAPI: loginAPI, discoverAPI: discoverAPI)

        let controller = operation.start(
            params: LoginOperationParams(accessToken: testAccessToken("input-access"), loginID: testLoginID(), traceParent: "trace-token")
        )
        let result = try await withOperationTimeout("login token success") { await controller.whenSettled() }

        let responseEnvelope = try requireOperationSuccess(result)
        guard case .success(let response) = responseEnvelope else {
            return try #require(nil as Void?, "Expected successful LoginResponse, got \(responseEnvelope)")
        }
        #expect(response.accessToken == testAccessToken("token-route-access"))
        #expect(loginAPI.params.get().count == 1)
        #expect(loginAPI.params.get().first??.accessToken == testAccessToken("input-access"))
        #expect(discoverAPI.params.get().isEmpty)
    }

    @Test func `Login discover maps API failure to terminal operation failure`() async throws {
        let loginID = testLoginID("blocked@example.test")
        let loginAPI = FakeLoginAPI(result: .success(testLoginResponse("unused")))
        let discoverAPI = FakeDiscoverAPI(result: .failure(.forbidden(errorCode: .forbidden, message: "Discover forbidden")))
        let operation = makeLoginOperation(loginAPI: loginAPI, discoverAPI: discoverAPI)

        let controller = operation.start(params: LoginOperationParams(loginID: loginID))
        let result = try await withOperationTimeout("login discover failure") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        guard case .access = failure else {
            return try #require(nil as Void?, "Expected access failure, got \(failure)")
        }
        #expect(failure.errorCode == .forbidden)
        #expect(failure.message == "Discover forbidden")
        #expect(loginAPI.params.get().isEmpty)
        #expect(discoverAPI.params.get().first??.loginID == loginID)
    }

    @Test func `Login maps API cancellation to system cancellation terminal result`() async throws {
        let operation = makeLoginOperation(
            loginAPI: FakeLoginAPI(result: .canceled),
            discoverAPI: FakeDiscoverAPI(result: .success(testLoginResponse("unused")))
        )

        let controller = operation.start(params: LoginOperationParams(accessToken: testAccessToken()))
        let result = try await withOperationTimeout("login API cancellation") { await controller.whenSettled() }

        let reason = try requireOperationCancellation(result)
        #expect(reason.description == Reason.systemError(details: "Operation canceled").description)
    }

    @Test func `Login rejects missing token and login ID without API calls`() async throws {
        let loginAPI = FakeLoginAPI(result: .success(testLoginResponse("unused")))
        let discoverAPI = FakeDiscoverAPI(result: .success(testLoginResponse("unused")))
        let operation = makeLoginOperation(loginAPI: loginAPI, discoverAPI: discoverAPI)

        let controller = operation.start(params: LoginOperationParams())
        let result = try await withOperationTimeout("login missing inputs") { await controller.whenSettled() }

        let failure = try requireOperationFailure(result)
        #expect(failure.errorCode == .invalidArgument)
        #expect(failure.message == "AccessToken or LoginId required")
        #expect(loginAPI.params.get().isEmpty)
        #expect(discoverAPI.params.get().isEmpty)
    }

    private func makeLoginOperation(
        loginAPI: FakeLoginAPI,
        discoverAPI: FakeDiscoverAPI,
        context: Context? = nil,
        validator: FakeLoginIDValidator = FakeLoginIDValidator()
    ) -> LoginOperationImpl {
        LoginOperationImpl(
            operationType: .sessionCreation,
            operationRegistry: OperationRegistryImpl(logger: nil),
            loginIDValidator: validator,
            loginAPI: loginAPI,
            discoverAPI: discoverAPI,
            context: context,
            logger: nil,
            taskScope: testTaskScope()
        )
    }
}

struct LoginIDCollectOperationImplementationTests {

    @Test func `Login ID collect completes valid params login ID without UI`() async throws {
        let ui = FakeLoginIDCollectUI()
        let operation = makeCollectOperation(ui: ui)

        let controller = operation.start(params: LoginIDCollectOperationParams(loginID: testLoginID()))
        let result = try await withOperationTimeout("login ID collect params success") { await controller.whenSettled() }

        #expect(result.getOrNil() == testLoginID())
        #expect(ui.startCount.get() == 0)
    }

    @Test func `Login ID collect completes valid context raw login ID without UI`() async throws {
        let ui = FakeLoginIDCollectUI()
        let context = testContext(authz: .start("raw@example.test"))
        let operation = makeCollectOperation(ui: ui, context: context)

        let controller = operation.start(params: LoginIDCollectOperationParams())
        let result = try await withOperationTimeout("login ID collect context success") { await controller.whenSettled() }

        #expect(result.getOrNil() == testLoginID("raw@example.test"))
        #expect(ui.startCount.get() == 0)
    }

    private func makeCollectOperation(
        ui: FakeLoginIDCollectUI,
        context: Context? = nil,
        validator: FakeLoginIDValidator = FakeLoginIDValidator()
    ) -> LoginIDCollectOperationImpl {
        LoginIDCollectOperationImpl(
            operationType: .loginIDCollect,
            operationRegistry: OperationRegistryImpl(logger: nil),
            loginIDConfig: FakeLoginIDConfigurationProvider(
                configuration: LoginIDConfiguration(
                    supportedTypes: [.email, .phoneNumber, .userName],
                    validationRegexes: [.email: nil, .phoneNumber: nil, .userName: nil]
                )
            ),
            loginIDValidator: validator,
            ui: ui,
            taskScope: testTaskScope(),
            errorStringsProvider: nil,
            context: context,
            logger: nil
        )
    }
}

private struct TestError: Error, Sendable {}
