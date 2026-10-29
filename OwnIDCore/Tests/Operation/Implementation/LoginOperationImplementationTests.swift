import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: OPS-080
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

    @Test(arguments: ["new_backend_code", "unknown"])
    func `Login keeps unsupported response codes separate from business unknown`(_ rawErrorCode: String) async throws {
        let baseURL = URL(string: "https://example.test/api")!
        let loginID = testLoginID()
        let body = #"{"errorCode":"\#(rawErrorCode)","message":"x"}"#
        let call = try DiscoverAPICall(apiBaseURL: baseURL, coder: JSONCoderImpl(), loginID: loginID, traceParent: nil)
        let apiFailure = call.mapHttpError(.init(url: baseURL.appendingPathComponent("login"), statusCode: 400, headers: [:], body: body))
        let operation = makeLoginOperation(
            loginAPI: FakeLoginAPI(result: .success(testLoginResponse("unused"))),
            discoverAPI: FakeDiscoverAPI(result: .failure(apiFailure))
        )
        let controller = operation.start(params: LoginOperationParams(loginID: loginID))
        let result = try await withOperationTimeout("login response code classification") { await controller.whenSettled() }
        let failure = try requireOperationFailure(result)
        #expect(failure.errorCode == .unknown)

        if rawErrorCode == "unknown" {
            guard case .input(.invalidRequest(_, let message, let cause)) = failure,
                let discoverFailure = cause as? DiscoverAPIFailure,
                case .badRequest(.unknown(let errorCode, let apiMessage)) = discoverFailure
            else {
                return try #require(nil as Void?, "Expected business unknown input failure, got \(failure)")
            }
            #expect(errorCode == .unknown)
            #expect(message == "x")
            #expect(apiMessage == "x")
        } else {
            guard case .unexpected(_, let message, let cause, let underlyingError) = failure,
                let discoverFailure = cause as? DiscoverAPIFailure,
                case .unexpected(let errorCode, let apiMessage, _) = discoverFailure
            else {
                return try #require(nil as Void?, "Expected unexpected API and operation failure, got \(failure)")
            }
            #expect(errorCode == .unknown)
            #expect(message == apiMessage)
            #expect(message.contains(rawErrorCode))
            let unexpectedError = try #require(underlyingError as? APIUnexpectedError)
            guard case .apiContract(let contract) = unexpectedError.cause,
                case .httpError(let response) = contract.failure
            else {
                return try #require(nil as Void?, "Expected HTTP API contract cause, got \(unexpectedError)")
            }
            #expect(response.statusCode == 400)
            #expect(response.body == body)
            let decodeError = try #require(contract.error)
            let diagnostic = try #require((decodeError as NSError).userInfo[NSDebugDescriptionErrorKey] as? String)
            #expect(diagnostic.contains(rawErrorCode))
        }
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

// Covers: OPS-090
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

    @Test func `Availability does not capture the collection configuration version`() async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let ui = FakeLoginIDCollectUI()
        let operation = makeCollectOperation(ui: ui, appConfigProvider: config, taskScope: scope)

        assertAvailable(await operation.availability(params: nil))
        #expect(config.readCount.get() == 0)
        config.set(.default.withLocalVersion(1))
        let controller = operation.start(params: .init(loginID: testLoginID()))

        #expect(try requireOperationSuccess(await collectResult(controller)) == testLoginID())
        #expect(ui.startCount.get() == 0)
    }

    @Test(arguments: [-1, 0])
    func `First synchronous start retains its nil snapshot across repeated starts`(publishedVersion: Int) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider()
        let ui = FakeLoginIDCollectUI()
        let validator = FakeLoginIDValidator()
        let operation = makeCollectOperation(ui: ui, validator: validator, appConfigProvider: config, taskScope: scope)

        let controller = try await MainActor.run { () throws -> LoginIDCollectOperationControllerImpl in
            let firstController = operation.start(params: .init(loginID: testLoginID())) as? LoginIDCollectOperationControllerImpl
            let first = try #require(firstController)
            let reads = config.readCount.get()
            config.set(.default.withLocalVersion(publishedVersion))
            let repeatedController = operation.start(params: .init(loginID: testLoginID())) as? LoginIDCollectOperationControllerImpl
            let repeated = try #require(repeatedController)
            #expect(first === repeated)
            #expect(config.readCount.get() == reads)
            return first
        }

        try await assertConfigurationFailure(controller)
        #expect(validator.validationCalls.get().isEmpty)
        #expect(ui.startCount.get() == 0)
    }

    @Test(arguments: [false, true])
    func `Initial validation publication overrides success and failure without opening UI`(invalid: Bool) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let validator = FakeLoginIDValidator(
            invalidIDs: invalid ? [testLoginID().id] : [],
            onValidate: { _ in config.set(.default.withLocalVersion(1)) }
        )
        let ui = FakeLoginIDCollectUI()
        let operation = makeCollectOperation(ui: ui, validator: validator, appConfigProvider: config, taskScope: scope)

        try await assertConfigurationFailure(operation.start(params: .init(loginID: testLoginID())))
        #expect(validator.validationCalls.get() == [testLoginID()])
        #expect(ui.startCount.get() == 0)
    }

    @Test(arguments: [false, true])
    func `Raw classification publication stops resolution on success and failure`(unsupported: Bool) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let validator = FakeLoginIDValidator(
            supportedTypes: unsupported ? [.phoneNumber] : [.email],
            onDetermine: { _ in config.set(.default.withLocalVersion(1)) }
        )
        let ui = FakeLoginIDCollectUI()
        let operation = makeCollectOperation(
            ui: ui,
            context: testContext(authz: .start("raw@example.test")),
            validator: validator,
            appConfigProvider: config,
            taskScope: scope
        )

        try await assertConfigurationFailure(operation.start())
        #expect(validator.determineCalls.get() == ["raw@example.test"])
        #expect(validator.validationCalls.get().isEmpty)
        #expect(ui.startCount.get() == 0)
    }

    @Test func `Publication during the first failed form validation stops later types`() async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let validator = FakeLoginIDValidator(
            invalidIDs: [""],
            onValidate: { _ in config.set(.default.withLocalVersion(1)) }
        )
        let ui = FakeLoginIDCollectUI()
        let operation = makeCollectOperation(ui: ui, validator: validator, appConfigProvider: config, taskScope: scope)
        let controller = operation.start()
        let state = try await activeState(ui)

        state.onContinue()

        try await assertConfigurationFailure(controller)
        #expect(validator.validationCalls.get() == [testLoginID("", type: .email)])
    }

    @Test(arguments: [false, true])
    func `UI startup publication wins over a returned UI error`(returnsError: Bool) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let ui = FakeLoginIDCollectUI(onStart: {
            config.set(.default.withLocalVersion(1))
            return returnsError ? .ui(errorCode: .integrationError, message: "startup failed") : nil
        })
        let operation = makeCollectOperation(ui: ui, appConfigProvider: config, taskScope: scope)

        try await assertConfigurationFailure(operation.start())
        #expect(ui.startCount.get() == 1)
    }

    @Test func `Registry callback publication stops validation and UI startup`() async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let logger = OwnIDLogRouter(
            ownIDLoggerProvider: {
                config.set(.default.withLocalVersion(1))
                return nil
            },
            serverLoggerProvider: { nil }
        )
        let registry = OperationRegistryImpl(logger: logger)
        let validator = FakeLoginIDValidator()
        let ui = FakeLoginIDCollectUI()
        let operation = makeCollectOperation(
            ui: ui,
            validator: validator,
            appConfigProvider: config,
            taskScope: scope,
            registry: registry
        )

        try await assertConfigurationFailure(operation.start(params: .init(loginID: testLoginID())))
        #expect(validator.validationCalls.get().isEmpty)
        #expect(ui.startCount.get() == 0)
        #expect(await MainActor.run { registry.operations.isEmpty })
    }

    @Test func `An equal snapshot version leaves the form active`() async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let ui = FakeLoginIDCollectUI(onStart: {
            config.set(.default.withLocalVersion(0))
            return nil
        })
        let operation = makeCollectOperation(ui: ui, appConfigProvider: config, taskScope: scope)
        let controller = operation.start()
        let state = try await activeState(ui)

        state.onCancel()

        #expect(try requireOperationCancellation(await collectResult(controller)).description == Reason.userClose().description)
    }

    @Test(arguments: [false, true])
    func `Click publication blocks Continue validation and preserves explicit Cancel`(cancel: Bool) async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let uiReturned = Locked(false)
        let checkedAfterUI = AsyncSignalRecorder<Void>()
        let config = FakeAppConfigProvider(
            config: .default.withLocalVersion(0),
            onRead: {
                if uiReturned.get() { checkedAfterUI.append(()) }
            }
        )
        let validator = FakeLoginIDValidator()
        let ui = FakeLoginIDCollectUI(onStart: {
            uiReturned.set(true)
            return nil
        })
        let operation = makeCollectOperation(ui: ui, validator: validator, appConfigProvider: config, taskScope: scope)
        let controller = operation.start(params: .init(onUIClick: { _ in config.set(.default.withLocalVersion(1)) }))
        let state = try await activeState(ui)
        _ = try await checkedAfterUI.waitForFirst("collection checked after UI startup") { _ in true }

        if cancel {
            state.onCancel()
            let reason = try requireOperationCancellation(await collectResult(controller))
            #expect(reason.description == Reason.userClose().description)
            let concreteController = controller as? LoginIDCollectOperationControllerImpl
            let concrete = try #require(concreteController)
            let completed = await MainActor.run { concrete.state }
            guard case .completed(let result) = completed else {
                Issue.record("Expected completed cancellation state")
                return
            }
            #expect(try requireOperationCancellation(result).description == reason.description)
        } else {
            state.onContinue()
            try await assertConfigurationFailure(controller)
        }
        #expect(validator.validationCalls.get().isEmpty)
    }

    @Test func `An error strings continuation checks publication without another UI action`() async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let uiReturned = Locked(false)
        let checkedAfterUI = AsyncSignalRecorder<Void>()
        let config = FakeAppConfigProvider(
            config: .default.withLocalVersion(0),
            onRead: {
                if uiReturned.get() { checkedAfterUI.append(()) }
            }
        )
        let strings = CollectConfigStringsProvider()
        defer { strings.finish() }
        let ui = FakeLoginIDCollectUI(onStart: {
            uiReturned.set(true)
            return nil
        })
        let operation = makeCollectOperation(ui: ui, appConfigProvider: config, taskScope: scope, errorStringsProvider: strings)
        _ = try await strings.nextRequested.waitForFirst("collection waiting for strings update") { _ in true }
        let controller = operation.start()
        _ = try await activeState(ui)
        _ = try await checkedAfterUI.waitForFirst("collection checked before strings update") { _ in true }

        config.set(.default.withLocalVersion(1))
        strings.emit()

        try await assertConfigurationFailure(controller)
    }

    @Test func `A completed collection keeps its result after publication and a late abort`() async throws {
        let scope = testTaskScope()
        defer { scope.shutdown() }
        let config = FakeAppConfigProvider(config: .default.withLocalVersion(0))
        let operation = makeCollectOperation(ui: FakeLoginIDCollectUI(), appConfigProvider: config, taskScope: scope)
        let controller = operation.start(params: .init(loginID: testLoginID()))
        #expect(try requireOperationSuccess(await collectResult(controller)) == testLoginID())

        config.set(.default.withLocalVersion(1))
        controller.abort(reason: .userClose())

        #expect(try requireOperationSuccess(await collectResult(controller)) == testLoginID())
        let concreteController = controller as? LoginIDCollectOperationControllerImpl
        let concrete = try #require(concreteController)
        let state = await MainActor.run { concrete.state }
        guard case .completed(let result) = state else {
            Issue.record("Expected completed state")
            return
        }
        #expect(try requireOperationSuccess(result) == testLoginID())
    }

    @Test func `Missing AppConfig provider uses the existing unavailable operation path`() async throws {
        let container = DIContainerImpl(scopeName: "collect-missing-app-config")
        let registry = OperationRegistryImpl(logger: nil)
        container.register((any OperationRegistry).self, instance: registry)
        let operation = LoginIDCollectOperationImpl.create(resolver: container)

        assertUnavailable(await operation.availability(params: nil))
        let result = try await collectResult(operation.start())
        #expect(try requireOperationFailure(result).message.contains("AppConfigProvider"))
        #expect(await MainActor.run { registry.operations.isEmpty })
    }

    private func collectResult(
        _ controller: any OperationController<LoginID, LoginIDCollectOperationFailure>
    ) async throws -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        let results = AsyncSignalRecorder<OperationResult<LoginID, LoginIDCollectOperationFailure>>()
        let settlement = Task { results.append(await controller.whenSettled()) }
        defer { settlement.cancel() }
        return try await results.waitForFirst("login ID collection settlement") { _ in true }
    }

    private func assertConfigurationFailure(
        _ controller: any OperationController<LoginID, LoginIDCollectOperationFailure>
    ) async throws {
        let failure = try requireOperationFailure(await collectResult(controller))
        guard case .unexpected = failure else {
            Issue.record("Expected an unexpected configuration failure, got \(failure)")
            return
        }
        #expect(failure.errorCode == .integrationError)
        #expect(failure.message == "App configuration changed. Restart the operation.")
        let concreteController = controller as? LoginIDCollectOperationControllerImpl
        let concrete = try #require(concreteController)
        let state = await MainActor.run { concrete.state }
        guard case .completed(let result) = state else {
            Issue.record("Expected completed state")
            return
        }
        #expect(try requireOperationFailure(result).description == failure.description)
    }

    private func activeState(_ ui: FakeLoginIDCollectUI) async throws -> LoginIDCollectUIState {
        let controller = try await withOperationTimeout("collection UI") { try await ui.controller.waitUnlessCancelled() }
        let states = await controller.stateStream()
        return try await withOperationTimeout("active collection state") {
            for await state in states {
                if case .active(let uiState) = state { return uiState }
            }
            throw OperationTestTimeout.streamEnded("active collection state")
        }
    }

    private func makeCollectOperation(
        ui: FakeLoginIDCollectUI,
        context: Context? = nil,
        validator: FakeLoginIDValidator = FakeLoginIDValidator(),
        appConfigProvider: any AppConfigProvider = FakeAppConfigProvider(),
        taskScope: TaskScope = testTaskScope(),
        errorStringsProvider: (any ErrorStringsProvider)? = nil,
        registry: OperationRegistryImpl = OperationRegistryImpl(logger: nil)
    ) -> LoginIDCollectOperationImpl {
        LoginIDCollectOperationImpl(
            operationType: .loginIDCollect,
            operationRegistry: registry,
            appConfigProvider: appConfigProvider,
            loginIDConfig: FakeLoginIDConfigurationProvider(
                configuration: LoginIDConfiguration(
                    supportedTypes: [.email, .phoneNumber, .userName],
                    validationRegexes: [.email: nil, .phoneNumber: nil, .userName: nil]
                )
            ),
            loginIDValidator: validator,
            ui: ui,
            taskScope: taskScope,
            errorStringsProvider: errorStringsProvider,
            context: context,
            logger: nil
        )
    }
}

private final class CollectConfigStringsProvider: ErrorStringsProvider, Sendable {
    let nextRequested = AsyncSignalRecorder<Void>()
    private let updates: AsyncStream<ErrorStrings?>
    private let continuation: AsyncStream<ErrorStrings?>.Continuation

    init() {
        var continuation: AsyncStream<ErrorStrings?>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func getStrings(params: ErrorStringsParams) -> AsyncStream<ErrorStrings?> {
        AsyncStream(
            unfolding: { [updates, nextRequested] in
                var iterator = updates.makeAsyncIterator()
                nextRequested.append(())
                return await iterator.next()
            },
            onCancel: { [continuation] in continuation.finish() }
        )
    }

    func emit() { continuation.yield(.default) }
    func finish() { continuation.finish() }
}

private struct TestError: Error, Sendable {}
