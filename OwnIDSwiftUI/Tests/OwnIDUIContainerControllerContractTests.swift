import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore
@testable import OwnIDSwiftUI

@MainActor
struct OwnIDUIContainerControllerContractTests {
    private let userCloseReason = Reason.userClose(details: "Operation container closed").description

    @Test func `Container opens once then closes with user close reason`() {
        var closeActionCount = 0
        var closedReasons: [String?] = []
        let controller = OwnIDUIContainerController {
            closeActionCount += 1
        }

        #expect(controller.isOpened == false)
        #expect(controller.isClosing == false)
        #expect(controller.isClosed == false)

        controller.addClosedHandler { reason in closedReasons.append(reason?.description) }
        controller.markOpened()
        controller.markOpened()

        #expect(controller.isOpened)
        #expect(controller.isClosing == false)
        #expect(closeActionCount == 0)

        controller.close()
        controller.close()

        #expect(controller.isOpened)
        #expect(controller.isClosing)
        #expect(closeActionCount == 1)
        #expect(closedReasons.isEmpty)

        controller.markClosed()
        controller.markClosed()

        #expect(controller.isOpened == false)
        #expect(controller.isClosing)
        #expect(controller.isClosed)
        #expect(closeActionCount == 1)
        #expect(closedReasons == [userCloseReason])
    }

    @Test func `Container closed without prior close still reports user close`() {
        var closeActionCount = 0
        var closedReason: String?
        let controller = OwnIDUIContainerController {
            closeActionCount += 1
        }

        controller.addClosedHandler { reason in closedReason = reason?.description }
        controller.markClosed()

        #expect(controller.isOpened == false)
        #expect(controller.isClosed)
        #expect(closeActionCount == 0)
        #expect(closedReason == userCloseReason)
    }

    @Test func `Dismiss without abort closes action once and reports no abort reason`() {
        var closeActionCount = 0
        var closedReasons: [String?] = []
        let controller = OwnIDUIContainerController {
            closeActionCount += 1
        }

        controller.addClosedHandler { reason in closedReasons.append(reason?.description) }
        controller.requestDismissWithoutAbort()
        controller.close()
        controller.markClosed()

        #expect(controller.isClosed)
        #expect(closeActionCount == 1)
        #expect(closedReasons == [nil])
    }

    @Test func `Closed handlers added after terminal close run immediately`() {
        var firstReason: String?
        var secondReason: String?
        let controller = OwnIDUIContainerController(closeAction: {})

        controller.close()
        controller.markClosed()
        controller.addClosedHandler { reason in firstReason = reason?.description }
        controller.addClosedHandler { reason in secondReason = reason?.description }

        #expect(firstReason == userCloseReason)
        #expect(secondReason == userCloseReason)
    }
}
