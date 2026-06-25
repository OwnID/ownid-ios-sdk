import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct BoostFlowOrchestrationTests {

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

    init(events: BoostFlowEventLog) {
        self.events = events
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
