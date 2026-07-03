import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: FLOW-080
struct EliteFlowImplWebBridgeParamsTests {

    @Test func `Elite context and failure descriptions keep stable categories`() {
        #expect(EliteFlowContext.empty.description == "EliteFlowContext()")
        #expect(
            EliteFlowFailure.operationFailed(
                errorCode: .integrationError,
                message: "web bridge unavailable"
            ).description == "OperationFailed(errorCode=integration_error, message=web bridge unavailable)"
        )
        #expect(
            EliteFlowFailure.unexpected(
                errorCode: .unknown,
                message: "unexpected settlement"
            ).description == "Unexpected(errorCode=unknown, message=unexpected settlement)"
        )
    }

    @Test func `Elite and WebBridge params default to server and SDK owned resolution`() {
        let emptyContext = EliteFlowContext.empty
        let defaultParams = WebBridgeOperationParams()
        let defaultOptions = WebBridgeOperationOptions()

        #expect(emptyContext.options == nil)
        #expect(emptyContext.eventsWrappers.isEmpty)

        #expect(defaultParams.options == nil)
        #expect(defaultParams.eventWrappers.isEmpty)
        #expect(defaultParams.onBaseUrlResolved == nil)

        #expect(defaultOptions.baseUrl == nil)
        #expect(defaultOptions.html == nil)
        #expect(defaultOptions.userAgent == nil)
        #expect(defaultOptions.webViewIsInspectable == false)
        #expect(defaultOptions.backgroundColor == nil)
        #expect(defaultOptions.limitsNavigationsToAppBoundDomains == false)
    }

    @Test func `Elite context options builder preserves pure WebBridge overrides without resolving runtime values`() throws {
        let context = EliteFlowContext { builder in
            builder.options { options in
                options.baseUrl = "https://login.example.test/path"
                options.html = "<html>elite override</html>"
                options.userAgent = "OwnIDEliteTest/1.0"
                options.webViewIsInspectable = true
                options.backgroundColor = .black
                options.limitsNavigationsToAppBoundDomains = true
            }
        }

        let options = try #require(context.options)

        #expect(options.baseUrl == "https://login.example.test/path")
        #expect(options.html == "<html>elite override</html>")
        #expect(options.userAgent == "OwnIDEliteTest/1.0")
        #expect(options.webViewIsInspectable == true)
        #expect(options.backgroundColor == .black)
        #expect(options.limitsNavigationsToAppBoundDomains == true)
        #expect(context.eventsWrappers.isEmpty)
    }

    @Test func `Elite start forwards context options and installs hosted terminal defaults`() async throws {
        let operation = CapturingWebBridgeOperation()
        let flow = EliteFlowImpl(
            webBridgeOperation: operation,
            userJourney: nil,
            taskScope: flowTaskScope(),
            logger: nil
        )
        let context = EliteFlowContext { builder in
            builder.options { options in
                options.baseUrl = "https://elite.example.test/page"
                options.html = "<html>elite</html>"
                options.userAgent = "EliteUA/1"
            }
            builder.events { events in
                events.onNativeAction { _, _, _ in }
            }
        }

        let controller = flow.start(context)
        let params = try await withFlowTimeout("captured Elite WebBridge params") {
            await operation.capturedParams.wait()
        }
        controller.abort(reason: .userClose(details: "test cleanup"))

        #expect(operation.genericStartParams.get().isEmpty)
        #expect(operation.webBridgeStartCount.get() == 1)
        #expect(params.options?.baseUrl == "https://elite.example.test/page")
        #expect(params.options?.html == "<html>elite</html>")
        #expect(params.options?.userAgent == "EliteUA/1")
        #expect(params.onBaseUrlResolved != nil)

        let actions = Set(params.eventWrappers.map(\.webBridgePluginAction))
        #expect(actions == ["onNativeAction", "onFinish", "onError", "onClose"])
        #expect(params.eventWrappers.filter(\.isTerminal).count == 4)
    }
}

private final class CapturingWebBridgeOperation: WebBridgeOperation, @unchecked Sendable {
    let operationType: OperationType = .webBridge
    let capturedParams = CapturedFlowValue<WebBridgeOperationParams>()
    let genericStartParams = FlowLocked<[WebBridgeOperationParams?]>([])
    let webBridgeStartCount = FlowLocked(0)

    func start(params: WebBridgeOperationParams?) -> any OperationController<Void, WebBridgeOperationFailure> {
        let controller = completedController()
        genericStartParams.mutate { $0.append(params) }
        return controller
    }

    func startWebBridge(params: WebBridgeOperationParams?) -> any WebBridgeOperationController {
        let controller = completedController()
        webBridgeStartCount.mutate { $0 += 1 }
        capturedParams.set(params ?? WebBridgeOperationParams())
        return controller
    }

    private func completedController() -> WebBridgeOperationControllerImpl {
        let controller = WebBridgeOperationControllerImpl(
            operationID: operationType.createOperationID(),
            onUserAborted: { _ in }
        )
        controller.complete(())
        return controller
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        .available
    }
}
