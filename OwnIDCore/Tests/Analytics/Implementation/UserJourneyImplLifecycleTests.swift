import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: ANALYTICS-020, ANALYTICS-RUNTIME-010, ANALYTICS-RUNTIME-020, ANALYTICS-RUNTIME-030, ANALYTICS-RUNTIME-040, ANALYTICS-RUNTIME-050
struct UserJourneyImplLifecycleTests {

    @Test func `Collector updates active flow metadata and preserves nil trace parent updates`() async throws {
        let harness = UserJourneyRuntimeHarness()

        await harness.userJourney.startFlow(name: "initial-flow", source: .widgetButton, traceParent: Self.traceParent)
        await harness.userJourney.startFlow(name: "updated-login", source: .explicit, traceParent: nil)
        harness.userJourney.completeFlow(.completed(nil))

        let params = try await harness.eventsAPI.waitForFirstParams()
        harness.shutdown()

        #expect(params.traceParent == Self.traceParent)
        #expect(params.userJourney.eventInfo.flows.count == 1)

        let flow = try #require(params.userJourney.eventInfo.flows.first)
        #expect(flow.name == "updated-login")
        #expect(flow.source == .explicit)
        #expect(flow.status == .completed)
        #expect(flow.switchedToFlow == nil)
    }

    @Test func `Collector switches flow and aborts in progress operation steps`() async throws {
        let harness = UserJourneyRuntimeHarness()
        let completedOperation = OperationID(type: .loginIDCollect, id: "login-id")
        let inProgressOperation = OperationID(type: .passkeyAuth, id: "old-passkey")

        await harness.userJourney.startFlow(name: "initial-flow", source: .widgetButton, traceParent: nil)
        await harness.userJourney.startOperation(operationID: completedOperation)
        await harness.userJourney.completeOperation(operationID: completedOperation, errorCode: nil, source: nil, message: nil)
        await harness.userJourney.startOperation(operationID: inProgressOperation)

        await harness.userJourney.switchToFlow(flowID: "flow-passkey", name: "passkey-enroll", source: .enrollPrompt)
        harness.userJourney.completeFlow(.registered(.passkey))

        let summary = try await harness.eventsAPI.waitForFirstSummary()
        harness.shutdown()

        #expect(summary.eventInfo.flows.count == 2)

        let switchedFlow = summary.eventInfo.flows[0]
        #expect(switchedFlow.status == .switched)
        #expect(switchedFlow.switchedToFlow == "flow-passkey")
        #expect(switchedFlow.completedAt != nil)

        let completedStep = try #require(switchedFlow.steps.first { $0.operationType == .loginIDCollect })
        #expect(completedStep.status == .completed)
        #expect(completedStep.completedAt != nil)

        let abortedStep = try #require(switchedFlow.steps.first { $0.operationType == .passkeyAuth })
        #expect(abortedStep.status == .aborted)
        #expect(abortedStep.completedAt != nil)

        let activeFlow = summary.eventInfo.flows[1]
        #expect(activeFlow.id == "flow-passkey")
        #expect(activeFlow.name == "passkey-enroll")
        #expect(activeFlow.source == .enrollPrompt)
        #expect(activeFlow.status == .completed)
        #expect(activeFlow.insights?.authMethod == .passkey)
        #expect(activeFlow.insights?.registered == true)
    }

    @Test func `Collector records operation clicks and failure diagnostics`() async throws {
        let harness = UserJourneyRuntimeHarness()
        let operation = OperationID(type: .loginIDCollect, id: "login-id")

        await harness.userJourney.startFlow(name: "login", source: .explicit, traceParent: nil)
        await harness.userJourney.startOperation(operationID: operation)
        await harness.userJourney.addOperationClick(operationID: operation)
        await harness.userJourney.addOperationClick(operationID: operation)
        await harness.userJourney.completeOperation(
            operationID: operation,
            errorCode: .timeout,
            source: "login-id",
            message: "timed out"
        )
        harness.userJourney.completeFlow(.completed(nil))

        let flow = try await harness.firstFlow()
        harness.shutdown()

        #expect(flow.insights?.clicksCount == 2)

        let step = try #require(flow.steps.first)
        #expect(flow.steps.count == 1)
        #expect(step.operationType == .loginIDCollect)
        #expect(step.status == .failed)
        #expect(step.completedAt != nil)
        #expect(step.errors?.first?.errorCode == ErrorCode.timeout.value)
        #expect(step.errors?.first?.source == "login-id")
        #expect(step.errors?.first?.message == "timed out")
        #expect(step.insights?.clicksCount == 2)
    }

    @Test func `Collector enriches reporter device and returning user summary data`() async throws {
        let loginID = LoginID(id: "user@example.com", type: .email)
        let harness = UserJourneyRuntimeHarness(
            userRepository: FakeUserRepository(lastUser: User(loginID: loginID, authMethod: .otp))
        )

        await harness.userJourney.startFlow(name: "login", source: .explicit, traceParent: nil)
        await harness.userJourney.setReferer("ios-app://com.example.app/account")
        await harness.userJourney.setUserInfo(loginID)
        await harness.userJourney.setUserInfo(loginID)
        harness.userJourney.completeFlow(.completed(nil))

        let summary = try await harness.eventsAPI.waitForFirstSummary()
        harness.shutdown()

        #expect(summary.reporter.service == .iosSdk)
        #expect(summary.reporter.origin == "com.example.app")
        #expect(summary.reporter.referer == "ios-app://com.example.app/account")
        #expect(summary.reporter.version == "1.2.3")

        #expect(summary.deviceInfo.isPlatformAuthenticatorAvailable)
        #expect(!summary.deviceInfo.isWebView)
        #expect(summary.deviceInfo.isMobileNative)

        let userInfo = try #require(summary.userInfo.first)
        #expect(summary.userInfo.count == 1)
        #expect(userInfo.loginId == loginID)
        #expect(userInfo.returningUser == true)
        #expect(userInfo.lastAuthMethod == .otp)
    }

    @Test func `Collector isolates last-user enrichment failure from journey submission`() async throws {
        let loginID = LoginID(id: "repository-failure@example.com", type: .email)
        let harness = UserJourneyRuntimeHarness(
            userRepository: FailingLastUserRepository()
        )

        await harness.userJourney.startFlow(name: "login", source: .explicit, traceParent: nil)
        await harness.userJourney.setUserInfo(loginID)
        harness.userJourney.completeFlow(.completed(.otp))

        let summary = try await harness.eventsAPI.waitForFirstSummary()
        harness.shutdown()

        #expect(summary.eventInfo.flows.first?.status == .completed)
        let userInfo = try #require(summary.userInfo.first)
        #expect(summary.userInfo.count == 1)
        #expect(userInfo.loginId == loginID)
        #expect(userInfo.returningUser == false)
        #expect(userInfo.lastAuthMethod == nil)
    }

    @Test func `Collector isolates payload construction failure from submitted terminal state`() async throws {
        let coder = CapturingThrowingEventsJSONCoder()
        let network = APIRecordingNetwork()
        let analyticsScope = TaskScope(shutdownToken: ShutdownToken())
        let userJourney = UserJourneyImpl(
            eventsApi: EventsAPIImpl(
                apiBaseURL: StaticAPIBaseURL(url: URL(string: "https://example.com")!),
                network: network,
                coder: coder,
                interceptor: nil
            ),
            localInfo: FakeLocalInfo(),
            userRepository: nil,
            taskScope: analyticsScope,
            logger: nil
        )
        let operation = OperationID(type: .passkeyAuth, id: "passkey-auth")

        await userJourney.startFlow(name: "login", source: .explicit, traceParent: Self.traceParent)
        await userJourney.startOperation(operationID: operation)
        await userJourney.completeOperation(operationID: operation, errorCode: nil, source: nil, message: nil)
        userJourney.completeFlow(.loggedIn(.passkey))

        let payload = try await coder.waitForFirstPayload()
        analyticsScope.shutdown()

        #expect(await network.requestCount() == 0)
        #expect(payload.traceparent == Self.traceParent)
        #expect(payload.eventInfo.flows.count == 1)

        let flow = try #require(payload.eventInfo.flows.first)
        #expect(flow.status == .completed)
        #expect(flow.insights?.authMethod == .passkey)
        #expect(flow.insights?.loggedIn == true)

        let step = try #require(flow.steps.first)
        #expect(flow.steps.count == 1)
        #expect(step.status == .completed)
    }

    @Test func `Collector starts fresh journey state after Events reporting failure`() async throws {
        let eventsAPI = CapturingEventsAPI(result: .failure(.badRequest(errorCode: .invalidArgument, message: "rejected")))
        let harness = UserJourneyRuntimeHarness(eventsAPI: eventsAPI)
        let firstLoginID = LoginID(id: "first@example.com", type: .email)

        await harness.userJourney.startFlow(name: "first-login", source: .explicit, traceParent: Self.traceParent)
        await harness.userJourney.setReferer("ios-app://com.example.app/first")
        await harness.userJourney.setUserInfo(firstLoginID)
        harness.userJourney.completeFlow(.error(errorCode: .network, source: "first-flow", message: "offline"))
        _ = try await eventsAPI.waitForFirstParams()

        await harness.userJourney.startFlow(name: "second-login", source: .implicit, traceParent: nil)
        harness.userJourney.completeFlow(.completed(.password))

        let params = try await eventsAPI.waitForParams(count: 2)
        harness.shutdown()

        let firstSummary = params[0].userJourney
        let secondParams = params[1]
        let secondSummary = secondParams.userJourney

        #expect(firstSummary.id != secondSummary.id)
        #expect(firstSummary.eventInfo.flows.count == 1)
        #expect(firstSummary.eventInfo.flows.first?.status == .failed)
        #expect(firstSummary.userInfo.first?.loginId == firstLoginID)

        #expect(secondParams.traceParent == nil)
        #expect(secondSummary.reporter.referer == "ios-app://com.example.app")
        #expect(secondSummary.userInfo.isEmpty)
        #expect(secondSummary.eventInfo.flows.count == 1)

        let secondFlow = try #require(secondSummary.eventInfo.flows.first)
        #expect(secondFlow.name == "second-login")
        #expect(secondFlow.source == .implicit)
        #expect(secondFlow.status == .completed)
        #expect(secondFlow.insights?.authMethod == .password)
    }

    @Test(
        arguments: [
            TerminalOutcomeCase(
                name: "logged in",
                outcome: .loggedIn(.password),
                expectedStatus: .completed,
                expectedAuthMethod: .password,
                expectedLoggedIn: true,
                expectedRegistered: nil,
                expectedErrorCode: nil
            ),
            TerminalOutcomeCase(
                name: "registered",
                outcome: .registered(.passkey),
                expectedStatus: .completed,
                expectedAuthMethod: .passkey,
                expectedLoggedIn: nil,
                expectedRegistered: true,
                expectedErrorCode: nil
            ),
            TerminalOutcomeCase(
                name: "completed",
                outcome: .completed(.otp),
                expectedStatus: .completed,
                expectedAuthMethod: .otp,
                expectedLoggedIn: nil,
                expectedRegistered: nil,
                expectedErrorCode: nil
            ),
            TerminalOutcomeCase(
                name: "aborted error",
                outcome: .error(errorCode: .aborted, source: "flow", message: "closed"),
                expectedStatus: .aborted,
                expectedAuthMethod: nil,
                expectedLoggedIn: nil,
                expectedRegistered: nil,
                expectedErrorCode: ErrorCode.aborted.value
            ),
            TerminalOutcomeCase(
                name: "failed error",
                outcome: .error(errorCode: .network, source: "flow", message: "offline"),
                expectedStatus: .failed,
                expectedAuthMethod: nil,
                expectedLoggedIn: nil,
                expectedRegistered: nil,
                expectedErrorCode: ErrorCode.network.value
            ),
        ]
    )
    func `Collector maps terminal outcomes into flow status insights and errors`(_ testCase: TerminalOutcomeCase)
        async throws
    {
        let harness = UserJourneyRuntimeHarness()

        await harness.userJourney.startFlow(name: "login", source: .explicit, traceParent: nil)
        harness.userJourney.completeFlow(testCase.outcome)

        let flow = try await harness.firstFlow()
        harness.shutdown()

        #expect(flow.status == testCase.expectedStatus, "\(testCase.name)")
        #expect(flow.completedAt != nil, "\(testCase.name)")
        #expect(flow.insights?.authMethod == testCase.expectedAuthMethod, "\(testCase.name)")
        #expect(flow.insights?.loggedIn == testCase.expectedLoggedIn, "\(testCase.name)")
        #expect(flow.insights?.registered == testCase.expectedRegistered, "\(testCase.name)")
        #expect(flow.errors?.first?.errorCode == testCase.expectedErrorCode, "\(testCase.name)")
    }

    @Test func `Collector replaces trace parent on explicit flow update`() async throws {
        let harness = UserJourneyRuntimeHarness()

        await harness.userJourney.startFlow(name: "initial-flow", source: .widgetButton, traceParent: Self.traceParent)
        await harness.userJourney.startFlow(name: "updated-login", source: .explicit, traceParent: Self.replacementTraceParent)
        harness.userJourney.completeFlow(.completed(nil))

        let params = try await harness.eventsAPI.waitForFirstParams()
        harness.shutdown()

        #expect(params.traceParent == Self.replacementTraceParent)
    }

    @Test func `Collector submits a best effort Events summary and flow result remains successful when reporting fails`() async throws {
        let loginID = FlowFixtures.loginID("analytics-failure@example.com")
        let accessToken = FlowFixtures.accessToken(id: loginID.id)
        let eventsAPI = CapturingEventsAPI(result: .failure(.badRequest(errorCode: .invalidArgument, message: "rejected")))
        let analyticsScope = TaskScope(shutdownToken: ShutdownToken())
        let userJourney = UserJourneyImpl(
            eventsApi: eventsAPI,
            localInfo: FakeLocalInfo(),
            userRepository: nil,
            taskScope: analyticsScope,
            logger: nil
        )
        let flowHarness = FlowTestHarness(loginResult: .success(FlowFixtures.loginSuccess(id: loginID.id)))
        var context = BoostFlowContext()
        context.accessToken = accessToken
        context.traceParent = Self.traceParent

        let flow = BoostLoginFlowImpl(
            userRepository: nil,
            ownIDOperation: flowHarness.operation,
            userJourney: userJourney,
            sessionCreate: nil,
            coder: flowHarness.coder,
            taskScope: flowHarness.taskScope,
            context: nil,
            loginIDValidator: flowHarness.validator,
            logger: nil
        )

        let response = try await requireSuccess(flow.start(context).whenSettled())
        let params = try await eventsAPI.waitForFirstParams()
        flowHarness.taskScope.shutdown()
        analyticsScope.shutdown()

        #expect(response.loginID == loginID)
        #expect(response.authMethod == .immediate)
        #expect(params.traceParent == Self.traceParent)
        #expect(params.userJourney.eventInfo.flows.count == 1)
        #expect(params.userJourney.eventInfo.flows.first?.status == .completed)
        #expect(params.userJourney.eventInfo.flows.first?.steps.first?.status == .completed)
    }

    private static let traceParent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
    private static let replacementTraceParent = "00-11111111111111111111111111111111-2222222222222222-01"
}

private struct UserJourneyRuntimeHarness: Sendable {
    let eventsAPI: CapturingEventsAPI
    let taskScope: TaskScope
    let userJourney: UserJourneyImpl

    init(
        eventsAPI: CapturingEventsAPI = CapturingEventsAPI(),
        localInfo: FakeLocalInfo = FakeLocalInfo(),
        userRepository: (any UserRepository)? = nil
    ) {
        self.eventsAPI = eventsAPI
        self.taskScope = TaskScope(shutdownToken: ShutdownToken())
        self.userJourney = UserJourneyImpl(
            eventsApi: eventsAPI,
            localInfo: localInfo,
            userRepository: userRepository,
            taskScope: taskScope,
            logger: nil
        )
    }

    func firstFlow(
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws -> FlowInfo {
        let summary = try await eventsAPI.waitForFirstSummary()
        return try #require(summary.eventInfo.flows.first, "Expected one analytics flow", sourceLocation: sourceLocation)
    }

    func shutdown() {
        taskScope.shutdown()
    }
}

struct TerminalOutcomeCase: Sendable, CustomTestStringConvertible {
    let name: String
    let outcome: UserJourneyOutcome
    let expectedStatus: FlowInfo.Status
    let expectedAuthMethod: AuthMethod?
    let expectedLoggedIn: Bool?
    let expectedRegistered: Bool?
    let expectedErrorCode: String?

    var testDescription: String { name }
}

private actor CapturingEventsAPI: EventsAPI {
    private let result: APIResult<Void, EventsFailure>
    private let params = AsyncSignalRecorder<EventsAPIParams>()

    init(result: APIResult<Void, EventsFailure> = .success(())) {
        self.result = result
    }

    func start(params: EventsAPIParams) async -> APIResult<Void, EventsFailure> {
        self.params.append(params)
        return result
    }

    func waitForFirstParams() async throws -> EventsAPIParams {
        try await params.waitForFirst("Expected analytics report") { _ in true }
    }

    func waitForFirstSummary() async throws -> UserJourneySummary {
        try await waitForFirstParams().userJourney
    }

    func waitForParams(count: Int) async throws -> [EventsAPIParams] {
        try await params.waitForCount(count, "Expected \(count) analytics reports") { _ in true }
    }
}

private final class CapturingThrowingEventsJSONCoder: JSONCoder, @unchecked Sendable {
    private let payloads = AsyncSignalRecorder<InternalUserJourneySummary>()
    private let backing = JSONCoderImpl()

    var encoder: JSONEncoder { backing.encoder }
    var decoder: JSONDecoder { backing.decoder }

    func encodeToString<T: Encodable>(_ value: T) throws -> String {
        if let payload = value as? InternalUserJourneySummary {
            payloads.append(payload)
        }
        throw CapturingThrowingEventsJSONCoderError.expected
    }

    func decodeFromString<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        try backing.decodeFromString(string, as: type)
    }

    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        try backing.encodeToJSONValue(value)
    }

    func decodeFromJSONValue<T: Decodable>(_ element: JSONValue, as type: T.Type) throws -> T {
        try backing.decodeFromJSONValue(element, as: type)
    }

    func waitForFirstPayload() async throws -> InternalUserJourneySummary {
        try await payloads.waitForFirst("Expected Events payload construction") { _ in true }
    }
}

private enum CapturingThrowingEventsJSONCoderError: Error {
    case expected
}

private struct FakeLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = []
    let bundleID = "com.example.app"
    let appVersion = "1.2.3"
    let userAgent = "OwnIDTest/1.2.3"
    let correlationId = "correlation-id"
    let isDebuggable = true
    let isSystemFidoCapable = true
    let isDeviceSecured = true
    let isFaceHardwarePresent = false
    let isFingerprintHardwarePresent = true
    let isStrongBiometricEnabled = true
}

private actor FakeUserRepository: UserRepository {
    private let storedLastUser: User?

    init(lastUser: User?) {
        self.storedLastUser = lastUser
    }

    func lastUser() async throws -> User? {
        storedLastUser
    }

    func setLastUser(_ user: User) async throws {}

    func clearLastUser() async {}
}

private enum FailingLastUserRepositoryError: Error {
    case expected
}

private actor FailingLastUserRepository: UserRepository {
    func lastUser() async throws -> User? {
        throw FailingLastUserRepositoryError.expected
    }

    func setLastUser(_ user: User) async throws {}

    func clearLastUser() async {}
}
