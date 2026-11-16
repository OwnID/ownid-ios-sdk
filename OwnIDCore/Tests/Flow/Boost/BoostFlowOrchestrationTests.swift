import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: FLOW-ORCH-010, FLOW-ORCH-020, FLOW-220
struct BoostFlowOrchestrationTests {

    @Test(arguments: [false, true])
    func `Login explicit abort and result have one ordered journey completion`(resultFirst: Bool) async throws {
        let events = BoostFlowEventLog()
        let harness = FlowTestHarness(loginResult: .success(.accountNotFound(.init())))
        defer { harness.taskScope.shutdown() }
        let completionGate = CapturedFlowValue<Void>()
        let journey = RecordingBoostFlowUserJourney(events: events, completionGate: resultFirst ? completionGate : nil)
        let abortReasons = FlowLocked<[Reason]>([])
        let operationID = OperationType.sessionCreation.createOperationID()
        let operationController = OperationControllerImpl<LoginResponse, LoginOperationFailure>(operationID: operationID) { reason in
            abortReasons.mutate { $0.append(reason) }
        }
        let operation = QueuedBoostLoginOperation(controllers: [operationController])
        harness.container.registerFactory((any LoginOperation).self, dependencies: []) { _ in operation }
        let flow = BoostLoginFlowImpl(
            ownIDOperation: harness.operation,
            userJourney: journey,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )
        var context = BoostFlowContext()
        context.accessToken = FlowFixtures.accessToken(id: "abort@example.test")
        let controller = flow.start(context)
        _ = try await withFlowTimeout("owned login operation started") {
            try #require(await operation.starts.first(where: { _ in true }))
        }
        let response = LoginResponse.success(.init(accessToken: FlowFixtures.accessToken(), sessionPayload: "session"))
        if resultFirst {
            operationController.complete(response)
            _ = try await withFlowTimeout("result journey completion entered") { await journey.completionStarted.wait() }
        }
        let reason = Reason.userClose(details: "explicit abort")
        controller.abort(reason: reason)
        controller.abort(reason: reason)
        if resultFirst { completionGate.set(()) }
        let first = try await withFlowTimeout("Boost terminal result") { await controller.whenSettled() }
        operationController.complete(response)
        _ = await operationController.whenSettled()
        let completions = journey.completedOperations.get()
        #expect(completions.count == 1)
        #expect(completions.first?.0 == operationID)
        let snapshot = events.snapshot()
        if resultFirst {
            _ = try requireSuccess(first)
            #expect(completions.first?.1 == nil)
            #expect(abortReasons.get().isEmpty)
        } else {
            #expect(try requireCancellation(first).description == reason.description)
            #expect(completions.first?.1 == .aborted)
            #expect(abortReasons.get().map(\.description) == [reason.description])
            #expect(try requireCancellation(await controller.whenSettled()).description == reason.description)
        }
        let stepIndex = try #require(snapshot.firstIndex(where: { $0.hasPrefix("journey.completeOperation:") }))
        let summaryIndex = try #require(snapshot.firstIndex(where: { $0.hasPrefix("journey.completeFlow:") }))
        #expect(stepIndex < summaryIndex)
        #expect(snapshot.filter { $0.hasPrefix("journey.completeFlow:") }.count == 1)
    }

    @Test(arguments: [false, true])
    func `Create explicit abort and result have one ordered journey completion`(resultFirst: Bool) async throws {
        let events = BoostFlowEventLog()
        let harness = FlowTestHarness(loginResult: .success(.accountNotFound(.init())))
        defer { harness.taskScope.shutdown() }
        let completionGate = CapturedFlowValue<Void>()
        let journey = RecordingBoostFlowUserJourney(events: events, completionGate: resultFirst ? completionGate : nil)
        let abortReasons = FlowLocked<[Reason]>([])
        let operationID = OperationType.sessionCreation.createOperationID()
        let operationController = OperationControllerImpl<LoginResponse, LoginOperationFailure>(operationID: operationID) { reason in
            abortReasons.mutate { $0.append(reason) }
        }
        let operation = QueuedBoostLoginOperation(controllers: [operationController])
        harness.container.registerFactory((any LoginOperation).self, dependencies: []) { _ in operation }
        let flow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation,
            boostLoginFlow: RecordingBoostLoginFlow(events: events, result: .failure(.unexpected(message: "unused child"))),
            userJourney: journey,
            sessionCreate: nil,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )
        var context = BoostFlowContext()
        context.accessToken = FlowFixtures.accessToken(id: "abort@example.test")
        let controller = flow.start(context)
        _ = try await withFlowTimeout("owned login operation started") {
            try #require(await operation.starts.first(where: { _ in true }))
        }
        let response = LoginResponse.success(.init(accessToken: FlowFixtures.accessToken(), sessionPayload: "session"))
        if resultFirst {
            operationController.complete(response)
            _ = try await withFlowTimeout("result journey completion entered") { await journey.completionStarted.wait() }
        }
        let reason = Reason.userClose(details: "explicit abort")
        controller.abort(reason: reason)
        controller.abort(reason: reason)
        if resultFirst { completionGate.set(()) }
        let first = try await withFlowTimeout("Boost terminal result") { await controller.whenSettled() }
        operationController.complete(response)
        _ = await operationController.whenSettled()
        let completions = journey.completedOperations.get()
        #expect(completions.count == 1)
        #expect(completions.first?.0 == operationID)
        let snapshot = events.snapshot()
        if resultFirst {
            _ = try requireSuccess(first)
            #expect(completions.first?.1 == nil)
            #expect(abortReasons.get().isEmpty)
        } else {
            #expect(try requireCancellation(first).description == reason.description)
            #expect(completions.first?.1 == .aborted)
            #expect(abortReasons.get().map(\.description) == [reason.description])
            #expect(try requireCancellation(await controller.whenSettled()).description == reason.description)
        }
        let stepIndex = try #require(snapshot.firstIndex(where: { $0.hasPrefix("journey.completeOperation:") }))
        let summaryIndex = try #require(snapshot.firstIndex(where: { $0.hasPrefix("journey.completeFlow:") }))
        #expect(stepIndex < summaryIndex)
        #expect(snapshot.filter { $0.hasPrefix("journey.completeFlow:") }.count == 1)
    }

    @Test func `Delegated Login owns its aborted step and the only summary`() async throws {
        let events = BoostFlowEventLog()
        let harness = FlowTestHarness(loginResult: .success(.accountNotFound(.init())))
        defer { harness.taskScope.shutdown() }
        let journey = RecordingBoostFlowUserJourney(events: events)
        let shutdownToken = ShutdownToken()
        let parentScope = TaskScope(shutdownToken: shutdownToken)
        let childScope = TaskScope(shutdownToken: shutdownToken)
        defer {
            parentScope.shutdown()
            childScope.shutdown()
        }
        let discoveryID = OperationType.sessionCreation.createOperationID()
        let childID = OperationType.sessionCreation.createOperationID()
        let discovery = OperationControllerImpl<LoginResponse, LoginOperationFailure>(operationID: discoveryID) { _ in }
        discovery.complete(.authRequired(.init(authRequirements: AuthRequirements(
            targetScore: 1, operations: [OperationRequirement(score: 1, type: .passkeyAuth, channels: nil)]
        ))))
        let abortReasons = FlowLocked<[Reason]>([])
        let childOperation = OperationControllerImpl<LoginResponse, LoginOperationFailure>(operationID: childID) { reason in
            abortReasons.mutate { $0.append(reason) }
        }
        let operation = QueuedBoostLoginOperation(controllers: [discovery, childOperation])
        harness.container.registerFactory((any LoginOperation).self, dependencies: []) { _ in operation }
        let childFlow = BoostLoginFlowImpl(
            ownIDOperation: harness.operation, userJourney: journey, sessionCreate: nil, coder: harness.coder,
            taskScope: childScope, context: nil, loginIDValidator: harness.validator, logger: nil
        )
        let parentFlow = BoostCreatePasskeyFlowImpl(
            ownIDOperation: harness.operation, boostLoginFlow: childFlow, userJourney: journey, sessionCreate: nil,
            coder: harness.coder, taskScope: parentScope, context: nil, loginIDValidator: harness.validator, logger: nil
        )
        var context = BoostFlowContext()
        context.accessToken = FlowFixtures.accessToken(id: "delegated-abort@example.test")
        let parent = parentFlow.start(context)
        _ = try await withFlowTimeout("delegated login operation started") {
            try #require(await operation.starts.first(where: { $0 == childID }))
        }
        let child = childFlow.start(BoostFlowContext())
        let reason = Reason.userClose(details: "delegated abort")
        parent.abort(reason: reason)
        parent.abort(reason: reason)
        let parentResult = try await withFlowTimeout("delegated parent abort") { await parent.whenSettled() }
        let childResult = try await withFlowTimeout("delegated child abort") { await child.whenSettled() }
        #expect(try requireCancellation(parentResult).description == reason.description)
        #expect(try requireCancellation(childResult).description == reason.description)
        childOperation.complete(.success(.init(accessToken: FlowFixtures.accessToken(), sessionPayload: "late")))
        _ = await childOperation.whenSettled()
        let completions = journey.completedOperations.get()
        #expect(completions.filter { $0.0 == discoveryID }.count == 1)
        #expect(completions.first { $0.0 == discoveryID }?.1 == nil)
        #expect(completions.filter { $0.0 == childID }.count == 1)
        #expect(completions.first { $0.0 == childID }?.1 == .aborted)
        #expect(abortReasons.get().map(\.description) == [reason.description])
        let snapshot = events.snapshot()
        #expect(snapshot.filter { $0.hasPrefix("journey.completeFlow:") }.count == 1)
        let stepIndex = try #require(snapshot.firstIndex(of: "journey.completeOperation:SessionCreation:aborted"))
        let summaryIndex = try #require(snapshot.firstIndex(of: "journey.completeFlow:error:aborted"))
        #expect(stepIndex < summaryIndex)
    }

    @Test func `Boost login settles after session storage and analytics terminal work`() async throws {
        let events = BoostFlowEventLog()
        let loginID = FlowFixtures.loginID("login-orchestration@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let sessionPayload = #"{"session":"payload"}"#
        let harness = FlowTestHarness(
            loginResult: .success(
                .success(LoginResponse.Success(accessToken: accessToken, sessionPayload: sessionPayload))
            ),
            loginIDCollectResult: .success(loginID)
        )
        let repository = RecordingBoostFlowUserRepository(events: events)
        let sessionCreate = RecordingBoostFlowSessionCreate(events: events, session: "host-session")
        let userJourney = RecordingBoostFlowUserJourney(events: events)
        let context = BoostFlowContext { builder in
            builder.loginID = loginID
        }

        let flow = BoostLoginFlowImpl(
            userRepository: repository,
            ownIDOperation: harness.operation,
            userJourney: userJourney,
            sessionCreate: sessionCreate,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await withFlowTimeout("Boost login orchestration settled") {
            try await requireSuccess(flow.start(context).whenSettled())
        }
        events.record("controller.settled")

        #expect(response.loginID == loginID)
        #expect(response.session as? String == "host-session")
        #expect(repository.savedUsers.map(\.loginID) == [loginID])
        #expect(repository.savedUsers.map(\.authMethod) == [.immediate])
        #expect(harness.loginIDCollect.startParams.count == 1)
        #expect(harness.login.startParams.count == 1)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
        #expect(
            events.snapshot() == [
                "journey.startFlow:login",
                "journey.startOperation:LoginIdCollect",
                "journey.completeOperation:LoginIdCollect:success",
                "journey.setUserInfo:login-orchestration@example.com",
                "journey.startOperation:SessionCreation",
                "journey.completeOperation:SessionCreation:success",
                "session.available",
                "session.create",
                "repository.setLastUser:login-orchestration@example.com:immediate",
                "journey.completeFlow:loggedIn:immediate",
                "controller.settled",
            ]
        )
    }

    @Test func `Boost create passkey existing-account path settles after session storage and analytics terminal work`() async throws {
        let events = BoostFlowEventLog()
        let loginID = FlowFixtures.loginID("create-existing@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let harness = FlowTestHarness(
            loginResult: .success(
                .success(LoginResponse.Success(accessToken: accessToken, sessionPayload: "existing-session"))
            ),
            loginIDCollectResult: .success(loginID)
        )
        let repository = RecordingBoostFlowUserRepository(events: events)
        let sessionCreate = RecordingBoostFlowSessionCreate(events: events, session: "existing-host-session")
        let userJourney = RecordingBoostFlowUserJourney(events: events)
        let context = BoostFlowContext { builder in
            builder.loginID = loginID
        }

        let flow = BoostCreatePasskeyFlowImpl(
            userRepository: repository,
            ownIDOperation: harness.operation,
            boostLoginFlow: RecordingBoostLoginFlow(
                events: events,
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: userJourney,
            sessionCreate: sessionCreate,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await withFlowTimeout("Boost create-passkey existing-account orchestration settled") {
            try await requireSuccess(flow.start(context).whenSettled())
        }
        events.record("controller.settled")
        let login = try requireLoginOutcome(response)

        #expect(login.loginID == loginID)
        #expect(login.session as? String == "existing-host-session")
        #expect(repository.savedUsers.map(\.loginID) == [loginID])
        #expect(repository.savedUsers.map(\.authMethod) == [.immediate])
        #expect(harness.loginIDCollect.startParams.count == 1)
        #expect(harness.login.startParams.count == 1)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
        #expect(
            events.snapshot() == [
                "journey.startFlow:create-passkey",
                "journey.startOperation:LoginIdCollect",
                "journey.completeOperation:LoginIdCollect:success",
                "journey.setUserInfo:create-existing@example.com",
                "journey.startOperation:SessionCreation",
                "journey.completeOperation:SessionCreation:success",
                "session.available",
                "session.create",
                "repository.setLastUser:create-existing@example.com:immediate",
                "journey.completeFlow:loggedIn:immediate",
                "controller.settled",
            ]
        )
    }

    @Test func `Boost create passkey registration path saves passkey user before registered analytics and settlement`() async throws {
        let events = BoostFlowEventLog()
        let loginID = FlowFixtures.loginID("create-registration@example.com")
        let proofToken = ProofToken(token: "registration-proof")
        let harness = FlowTestHarness(
            loginResult: .success(.accountNotFound(LoginResponse.AccountNotFound())),
            loginIDCollectResult: .success(loginID),
            passkeyAttestationResult: .success(
                FlowFixtures.attestationResponse(proofToken: proofToken, ownIdData: #"{"own":"data"}"#)
            )
        )
        let repository = RecordingBoostFlowUserRepository(events: events)
        let sessionCreate = RecordingBoostFlowSessionCreate(events: events)
        let userJourney = RecordingBoostFlowUserJourney(events: events)
        let context = BoostFlowContext { builder in
            builder.loginID = loginID
        }

        let flow = BoostCreatePasskeyFlowImpl(
            userRepository: repository,
            ownIDOperation: harness.operation,
            boostLoginFlow: RecordingBoostLoginFlow(
                events: events,
                result: .failure(.unexpected(message: "child login should not start"))
            ),
            userJourney: userJourney,
            sessionCreate: sessionCreate,
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await withFlowTimeout("Boost create-passkey registration orchestration settled") {
            try await requireSuccess(flow.start(context).whenSettled())
        }
        events.record("controller.settled")
        let created = try requireCreatePasskeyOutcome(response)

        #expect(created.loginID == loginID)
        #expect(created.proofToken == proofToken)
        #expect(repository.savedUsers.map(\.loginID) == [loginID])
        #expect(repository.savedUsers.map(\.authMethod) == [.passkey])
        #expect(sessionCreate.events.isEmpty)
        #expect(harness.loginIDCollect.startParams.count == 1)
        #expect(harness.login.startParams.count == 1)
        #expect(harness.passkeyAttestation.startParams.count == 1)
        #expect(
            events.snapshot() == [
                "journey.startFlow:create-passkey",
                "journey.startOperation:LoginIdCollect",
                "journey.completeOperation:LoginIdCollect:success",
                "journey.setUserInfo:create-registration@example.com",
                "journey.startOperation:SessionCreation",
                "journey.completeOperation:SessionCreation:success",
                "journey.startOperation:PasskeyCreation",
                "journey.completeOperation:PasskeyCreation:success",
                "repository.setLastUser:create-registration@example.com:passkey",
                "journey.completeFlow:registered:nil",
                "controller.settled",
            ]
        )
    }

    @Test func `Boost create passkey delegated login does not duplicate parent terminal storage or analytics`() async throws {
        let events = BoostFlowEventLog()
        let loginID = FlowFixtures.loginID("delegated-login@example.com")
        let childResponse = BoostFlowLoginResponse(
            loginID: loginID,
            authMethod: .passkey,
            accessToken: FlowFixtures.accessToken(id: loginID.id),
            sessionPayload: "child-session",
            session: "child-host-session"
        )
        let childFlow = RecordingBoostLoginFlow(events: events, result: .success(childResponse))
        let harness = FlowTestHarness(
            loginResult: .success(
                .authRequired(
                    LoginResponse.AuthRequired(
                        authRequirements: AuthRequirements(
                            targetScore: 1,
                            operations: [
                                OperationRequirement(score: 1, type: .passkeyAuth, channels: nil)
                            ]
                        )
                    )
                )
            ),
            loginIDCollectResult: .success(loginID)
        )
        let repository = RecordingBoostFlowUserRepository(events: events)
        let userJourney = RecordingBoostFlowUserJourney(events: events)
        let context = BoostFlowContext { builder in
            builder.loginID = loginID
        }

        let flow = BoostCreatePasskeyFlowImpl(
            userRepository: repository,
            ownIDOperation: harness.operation,
            boostLoginFlow: childFlow,
            userJourney: userJourney,
            sessionCreate: RecordingBoostFlowSessionCreate(events: events),
            coder: harness.coder,
            taskScope: harness.taskScope,
            context: nil,
            loginIDValidator: harness.validator,
            logger: nil
        )

        let response = try await withFlowTimeout("Boost create-passkey delegated-login orchestration settled") {
            try await requireSuccess(flow.start(context).whenSettled())
        }
        events.record("controller.settled")
        let login = try requireLoginOutcome(response)

        #expect(login.loginID == loginID)
        #expect(login.authMethod == .passkey)
        #expect(childFlow.contexts.count == 1)
        #expect(repository.savedUsers.isEmpty)
        #expect(harness.passkeyAttestation.startParams.isEmpty)
        #expect(
            events.snapshot() == [
                "journey.startFlow:create-passkey",
                "journey.startOperation:LoginIdCollect",
                "journey.completeOperation:LoginIdCollect:success",
                "journey.setUserInfo:delegated-login@example.com",
                "journey.startOperation:SessionCreation",
                "journey.completeOperation:SessionCreation:success",
                "journey.switchToFlow:login",
                "childLogin.start",
                "controller.settled",
            ]
        )
    }
}

private final class BoostFlowEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ event: String) {
        lock.withLock {
            values.append(event)
        }
    }

    func snapshot() -> [String] {
        lock.withLock { values }
    }
}

private final class RecordingBoostFlowUserRepository: UserRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let events: BoostFlowEventLog
    private var storedLastUser: User?
    private(set) var savedUsers: [User] = []

    init(events: BoostFlowEventLog, lastUser: User? = nil) {
        self.events = events
        self.storedLastUser = lastUser
    }

    func lastUser() async throws -> User? {
        events.record("repository.lastUser")
        return lock.withLock { storedLastUser }
    }

    func setLastUser(_ user: User) async throws {
        events.record("repository.setLastUser:\(user.loginID.id):\(user.authMethod.rawValue)")
        lock.withLock {
            storedLastUser = user
            savedUsers.append(user)
        }
    }

    func clearLastUser() async {
        events.record("repository.clearLastUser")
        lock.withLock {
            storedLastUser = nil
        }
    }
}

private final class RecordingBoostFlowSessionCreate: SessionCreate, @unchecked Sendable {
    private let lock = NSLock()
    private let eventLog: BoostFlowEventLog
    private let available: Bool
    private let session: (any Sendable)?
    private(set) var events: [String] = []

    init(events: BoostFlowEventLog, available: Bool = true, session: (any Sendable)? = "host-session") {
        self.eventLog = events
        self.available = available
        self.session = session
    }

    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        record("available")
        return available
    }

    @MainActor func create(params: SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable> {
        record("create")
        return .success(SessionOutput(session: session))
    }

    private func record(_ event: String) {
        eventLog.record("session.\(event)")
        lock.withLock {
            events.append(event)
        }
    }
}

private final class RecordingBoostFlowUserJourney: UserJourney, @unchecked Sendable {
    private let events: BoostFlowEventLog
    private let completionGate: CapturedFlowValue<Void>?
    let completionStarted = CapturedFlowValue<OperationID>()
    let completedOperations = FlowLocked<[(OperationID, ErrorCode?)]>([])

    init(events: BoostFlowEventLog, completionGate: CapturedFlowValue<Void>? = nil) {
        self.events = events
        self.completionGate = completionGate
    }

    func startFlow(name: String?, source: FlowInfo.Source, traceParent: String?) async {
        events.record("journey.startFlow:\(name ?? "nil")")
    }

    func switchToFlow(flowID: String?, name: String?, source: FlowInfo.Source) async {
        events.record("journey.switchToFlow:\(name ?? "nil")")
    }

    func setUserInfo(_ loginID: LoginID) async {
        events.record("journey.setUserInfo:\(loginID.id)")
    }

    func setReferer(_ referer: String) async {
        events.record("journey.setReferer")
    }

    func startOperation(operationID: OperationID) async {
        events.record("journey.startOperation:\(operationID.type.rawValue)")
    }

    func addOperationClick(operationID: OperationID) async {
        events.record("journey.addOperationClick:\(operationID.type.rawValue)")
    }

    func completeOperation(operationID: OperationID, errorCode: ErrorCode?, source: String?, message: String?) async {
        completionStarted.set(operationID)
        if let completionGate { await completionGate.wait() }
        completedOperations.mutate { $0.append((operationID, errorCode)) }
        events.record("journey.completeOperation:\(operationID.type.rawValue):\(errorCode?.rawValue ?? "success")")
    }

    nonisolated func completeFlow(_ outcome: UserJourneyOutcome) {
        events.record("journey.completeFlow:\(Self.describe(outcome))")
    }

    private static func describe(_ outcome: UserJourneyOutcome) -> String {
        switch outcome {
        case .loggedIn(let authMethod):
            return "loggedIn:\(authMethod.rawValue)"
        case .registered(let authMethod):
            return "registered:\(authMethod?.rawValue ?? "nil")"
        case .completed(let authMethod):
            return "completed:\(authMethod?.rawValue ?? "nil")"
        case .error(let errorCode, _, _):
            return "error:\(errorCode.rawValue)"
        }
    }
}

private final class RecordingBoostLoginFlow: BoostLoginFlow, @unchecked Sendable {
    private let lock = NSLock()
    private let events: BoostFlowEventLog
    private let result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>
    private(set) var contexts: [BoostFlowContext] = []

    init(events: BoostFlowEventLog, result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>) {
        self.events = events
        self.result = result
    }

    func start(_ context: BoostFlowContext) -> any BoostLoginFlowController {
        events.record("childLogin.start")
        lock.withLock {
            contexts.append(context)
        }
        let controller = FlowController<BoostFlowLoginResponse, BoostLoginFlowFailure>(onUserAborted: { _ in })
        switch result {
        case .success(let response):
            controller.complete(response)
        case .canceled(let reason):
            controller.cancel(reason)
        case .failure(let failure):
            controller.fail(failure)
        }
        return controller
    }
}

private final class QueuedBoostLoginOperation: LoginOperation, @unchecked Sendable {
    let operationType: OperationType = .sessionCreation
    let starts: AsyncStream<OperationID>
    private let continuation: AsyncStream<OperationID>.Continuation
    private let lock = NSLock()
    private var controllers: [OperationControllerImpl<LoginResponse, LoginOperationFailure>]

    init(controllers: [OperationControllerImpl<LoginResponse, LoginOperationFailure>]) {
        self.controllers = controllers
        let (stream, continuation) = AsyncStream.makeStream(of: OperationID.self)
        starts = stream
        self.continuation = continuation
    }

    func availability(params: (any CapabilityParams)?) async -> Availability { .available }

    func start(params: LoginOperationParams?) -> any OperationController<LoginResponse, LoginOperationFailure> {
        let controller = lock.withLock { controllers.count > 1 ? controllers.removeFirst() : controllers[0] }
        continuation.yield(controller.operationID)
        return controller
    }
}
