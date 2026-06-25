import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct EliteFlowImplWebBridgeFailureTests {

    @Test(arguments: WebBridgeFailureClassificationCase.allCases)
    func `Elite wraps WebBridge typed failures as operation failed consistently`(_ testCase: WebBridgeFailureClassificationCase)
        async throws
    {
        let webBridgeFailure = testCase.failure
        let webBridgeOperation = CompletedWebBridgeOperationFake(result: .failure(webBridgeFailure))
        let taskScope = flowTaskScope()
        defer { taskScope.shutdown() }
        let flow = EliteFlowImpl(
            webBridgeOperation: webBridgeOperation,
            userJourney: nil,
            taskScope: taskScope,
            logger: nil
        )

        let result = try await withFlowTimeout("Elite wrapping \(testCase.testDescription)") {
            await flow.start(.empty).whenSettled()
        }
        let failure = try requireFailure(result)

        guard
            case .operationFailed(
                let operationType,
                let errorCode,
                let message,
                let operationID,
                let operationFailure,
                let underlyingError
            ) = failure
        else {
            _ = try #require(nil as Void?, "Expected operationFailed, got \(failure)")
            return
        }

        #expect(operationType == .webBridge)
        #expect(errorCode == webBridgeFailure.errorCode)
        #expect(message == "Elite operation failed: \(webBridgeFailure.message)")
        #expect(operationID == webBridgeOperation.operationID)
        #expect(underlyingError == nil)

        let nestedFailure = try #require(operationFailure as? WebBridgeOperationFailure)
        try testCase.expectMatches(nestedFailure)
        #expect(webBridgeOperation.startCount.get() == 1)
    }
}

enum WebBridgeFailureClassificationCase: CaseIterable, Sendable, CustomTestStringConvertible {
    case precondition
    case ui
    case unexpected

    var testDescription: String {
        switch self {
        case .precondition: return "precondition"
        case .ui: return "ui"
        case .unexpected: return "unexpected"
        }
    }

    var failure: WebBridgeOperationFailure {
        switch self {
        case .precondition:
            return .precondition(errorCode: .integrationError, message: "origin precondition failed")
        case .ui:
            return .ui(.init(errorCode: .unknown, message: "web view runtime failed"))
        case .unexpected:
            return .unexpected(errorCode: .unknown, message: "unexpected bridge failure")
        }
    }

    func expectMatches(_ failure: WebBridgeOperationFailure) throws {
        switch (self, failure) {
        case (.precondition, .precondition(let errorCode, let message)):
            #expect(errorCode == .integrationError)
            #expect(message == "origin precondition failed")
        case (.ui, .ui(let ui)):
            #expect(ui.errorCode == .unknown)
            #expect(ui.message == "web view runtime failed")
        case (.unexpected, .unexpected(let errorCode, let message, let underlyingError)):
            #expect(errorCode == .unknown)
            #expect(message == "unexpected bridge failure")
            #expect(underlyingError == nil)
        default:
            _ = try #require(nil as Void?, "Unexpected nested WebBridge failure: \(failure)")
        }
    }
}

private final class CompletedWebBridgeOperationFake: WebBridgeOperation, @unchecked Sendable {
    let operationType: OperationType = .webBridge
    let operationID = OperationID(type: .webBridge, id: "elite-webbridge")
    let startCount = FlowLocked(0)
    private let result: OperationResult<Void, WebBridgeOperationFailure>

    init(result: OperationResult<Void, WebBridgeOperationFailure>) {
        self.result = result
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .available
    }

    func start(params: WebBridgeOperationParams?) -> any OperationController<Void, WebBridgeOperationFailure> {
        startCount.mutate { $0 += 1 }
        let controller = WebBridgeOperationControllerImpl(operationID: operationID, onUserAborted: { _ in })
        switch result {
        case .success:
            controller.complete(())
        case .canceled(let reason):
            controller.cancel(reason)
        case .failure(let failure):
            controller.fail(failure)
        }
        return controller
    }
}
