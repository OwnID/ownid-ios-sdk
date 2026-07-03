import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: FLOW-100, FLOW-110, FLOW-ORCH-030
struct EliteFlowImplWebBridgeSettlementTests {

    @Test func `Elite maps WebBridge success once`() async throws {
        let harness = EliteFlowHarness()
        let context = EliteFlowContext { builder in
            builder.options { options in
                options.baseUrl = "https://elite.example.test/hosted"
            }
        }

        let controller = harness.flow.start(context)
        let webBridgeController = try await harness.startedWebBridgeController()
        let params = try #require(harness.webBridge.startParams.get().compactMap { $0 }.first)
        let onBaseUrlResolved = try #require(params.onBaseUrlResolved)

        onBaseUrlResolved("https://elite.example.test/hosted")
        harness.webBridge.settle(.success(()))
        let result = try await harness.flowResult(controller, "elite success")

        try requireSuccess(result)
        let cached = await controller.whenSettled()
        try requireSuccess(cached)

        harness.webBridge.settle(.canceled(.userClose(details: "late cancel")))
        controller.abort(reason: .systemError(details: "late abort"))
        let afterLateEvents = await controller.whenSettled()
        try requireSuccess(afterLateEvents)

        try assertEliteJourneyStarted(harness.userJourney)
        try await assertReferers(harness.userJourney, ["https://elite.example.test/hosted"])
        #expect(params.options?.baseUrl == "https://elite.example.test/hosted")
        #expect(harness.userJourney.startedOperations.get() == [webBridgeController.operationID])
        let completion = try requireOperationCompletion(
            harness.userJourney.completedOperations.get(),
            operationID: webBridgeController.operationID
        )
        #expect(completion.errorCode == nil)
        #expect(completion.source == nil)
        #expect(completion.message == nil)
        try requireCompletedJourneyOutcome(harness.userJourney.completedOutcomes.get())
        #expect(webBridgeController.operationID == harness.webBridge.operationID)
        #expect(harness.webBridge.genericStartParams.get().isEmpty)
    }

    @Test func `Elite maps WebBridge failure once as operation failure`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        let webBridgeController = try await harness.startedWebBridgeController()

        let webBridgeFailure = WebBridgeOperationFailure.ui(
            .init(errorCode: .unknown, message: "Fake WebBridge UI failed")
        )
        harness.webBridge.settle(.failure(webBridgeFailure))
        let result = try await harness.flowResult(controller, "elite failure")

        let failure = try requireFailure(result)
        guard case .operationFailed(let operationType, let errorCode, let message, let operationID, let operationFailure, _) = failure
        else {
            _ = try #require(nil as Void?, "Expected operationFailed, got \(failure)")
            return
        }
        #expect(operationType == .webBridge)
        #expect(errorCode == .unknown)
        #expect(message == "Elite operation failed: Fake WebBridge UI failed")
        #expect(operationID == webBridgeController.operationID)
        #expect(operationFailure?.message == webBridgeFailure.message)

        harness.webBridge.settle(.success(()))
        controller.abort(reason: .userClose(details: "late abort"))
        let afterLateEvents = await controller.whenSettled()
        let cachedFailure = try requireFailure(afterLateEvents)
        #expect(cachedFailure.message == failure.message)
        try assertEliteJourneyStarted(harness.userJourney)
        #expect(harness.userJourney.startedOperations.get() == [webBridgeController.operationID])
        let completion = try requireOperationCompletion(
            harness.userJourney.completedOperations.get(),
            operationID: webBridgeController.operationID
        )
        #expect(completion.errorCode == webBridgeFailure.errorCode)
        #expect(completion.source == "EliteFlowActor.reduce.webBridgeOpResult.failure")
        #expect(completion.message == webBridgeFailure.message)
        let outcome = try requireErrorJourneyOutcome(harness.userJourney.completedOutcomes.get(), errorCode: webBridgeFailure.errorCode)
        #expect(outcome.source == "EliteFlowImpl.handleStateChange.failure")
        #expect(outcome.message == failure.message)
    }

    @Test func `Elite maps WebBridge cancellation once and preserves reason`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        let webBridgeController = try await harness.startedWebBridgeController()

        let expectedReason = Reason.userClose(details: "host canceled")
        harness.webBridge.settle(.canceled(expectedReason))
        let result = try await harness.flowResult(controller, "elite cancellation")

        let reason = try requireCancellation(result)
        #expect(reason.description == expectedReason.description)

        harness.webBridge.settle(.failure(.unexpected(message: "late failure")))
        controller.abort(reason: .systemError(details: "late abort"))
        let afterLateEvents = await controller.whenSettled()
        let cachedReason = try requireCancellation(afterLateEvents)
        #expect(cachedReason.description == expectedReason.description)
        try assertEliteJourneyStarted(harness.userJourney)
        #expect(harness.userJourney.startedOperations.get() == [webBridgeController.operationID])
        let completion = try requireOperationCompletion(
            harness.userJourney.completedOperations.get(),
            operationID: webBridgeController.operationID
        )
        #expect(completion.errorCode == .aborted)
        #expect(completion.source == "EliteFlowActor.reduce.webBridgeOpResult.canceled")
        #expect(completion.message == "Canceled with reason: \(expectedReason.description)")
        let outcome = try requireErrorJourneyOutcome(harness.userJourney.completedOutcomes.get(), errorCode: .aborted)
        #expect(outcome.source == "EliteFlowImpl.handleStateChange.canceled")
        #expect(outcome.message == "Canceled with reason: \(expectedReason.description)")
    }

    @Test func `Elite abort forwards to active WebBridge controller and settles with expected reason`() async throws {
        let harness = EliteFlowHarness()
        let controller = harness.flow.start(.empty)
        _ = try await harness.startedWebBridgeController()

        let expectedReason = Reason.systemError(details: "owner dismissed")
        controller.abort(reason: expectedReason)

        let result = try await harness.flowResult(controller, "elite abort")
        let reason = try requireCancellation(result)

        #expect(reason.description == expectedReason.description)
        let forwardedReason = try #require(harness.webBridge.abortReasons.get().first)
        #expect(forwardedReason.description == expectedReason.description)
        #expect(harness.userJourney.completedOutcomes.get().count == 1)
    }
}

private struct EliteFlowHarness {
    let webBridge: ControlledWebBridgeOperation
    let userJourney: RecordingFlowUserJourney
    let flow: EliteFlowImpl

    init() {
        self.webBridge = ControlledWebBridgeOperation()
        self.userJourney = RecordingFlowUserJourney()
        self.flow = EliteFlowImpl(
            webBridgeOperation: webBridge,
            userJourney: userJourney,
            taskScope: flowTaskScope(),
            logger: nil
        )
    }

    func startedWebBridgeController() async throws -> WebBridgeOperationControllerImpl {
        try await withFlowTimeout("webBridge start") {
            await webBridge.startedController.wait()
        }
    }

    func flowResult(
        _ controller: any EliteFlowController,
        _ description: String
    ) async throws -> FlowResult<Void, EliteFlowFailure> {
        try await withFlowTimeout(description) {
            await controller.whenSettled()
        }
    }
}

private final class ControlledWebBridgeOperation: WebBridgeOperation, @unchecked Sendable {
    let operationType: OperationType = .webBridge
    let operationID = OperationID(type: .webBridge, id: "web-bridge-flow-test")
    let startParams = FlowLocked<[WebBridgeOperationParams?]>([])
    let genericStartParams = FlowLocked<[WebBridgeOperationParams?]>([])
    let abortReasons = FlowLocked<[Reason]>([])
    let startedController = CapturedFlowValue<WebBridgeOperationControllerImpl>()

    private lazy var controller = WebBridgeOperationControllerImpl(operationID: operationID) { [abortReasons] reason in
        abortReasons.mutate { $0.append(reason) }
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .available
    }

    func start(params: WebBridgeOperationParams?) -> any OperationController<Void, WebBridgeOperationFailure> {
        genericStartParams.mutate { $0.append(params) }
        return recordStartedController()
    }

    func startWebBridge(params: WebBridgeOperationParams?) -> any WebBridgeOperationController {
        startParams.mutate { $0.append(params) }
        return recordStartedController()
    }

    private func recordStartedController() -> WebBridgeOperationControllerImpl {
        let controller = controller
        startedController.set(controller)
        return controller
    }

    func settle(_ result: OperationResult<Void, WebBridgeOperationFailure>) {
        switch result {
        case .success:
            controller.complete(())
        case .canceled(let reason):
            controller.cancel(reason)
        case .failure(let failure):
            controller.fail(failure)
        }
    }
}

private func assertEliteJourneyStarted(
    _ userJourney: RecordingFlowUserJourney,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    #expect(
        userJourney.startedFlows.get() == [RecordedUserJourneyFlow(name: "elite", source: .elite, traceParent: nil)],
        sourceLocation: sourceLocation
    )
}

private func assertReferers(
    _ userJourney: RecordingFlowUserJourney,
    _ expected: [String],
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) async throws {
    try await withFlowTimeout("Elite UserJourney referer") {
        while userJourney.referers.get() != expected {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    #expect(userJourney.referers.get() == expected, sourceLocation: sourceLocation)
}
