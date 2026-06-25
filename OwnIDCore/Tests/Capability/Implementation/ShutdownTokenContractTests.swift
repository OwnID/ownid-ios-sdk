import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct ShutdownTokenContractTests {

    @Test func `Cancellation handlers run once removed handlers do not run and late handlers run immediately`() throws {
        let token = ShutdownToken()
        let retainedHandlerCalls = LockedCounter()
        let removedHandlerCalls = LockedCounter()
        let immediateHandlerCalls = LockedCounter()

        _ = try #require(
            token.onCancel {
                _ = retainedHandlerCalls.increment()
            }
        )
        let removedID = try #require(
            token.onCancel {
                _ = removedHandlerCalls.increment()
            }
        )

        token.removeHandler(removedID)

        token.cancel()
        token.cancel()

        #expect(retainedHandlerCalls.value == 1)
        #expect(removedHandlerCalls.value == 0)

        let immediateID = token.onCancel {
            _ = immediateHandlerCalls.increment()
        }

        #expect(immediateID == nil)
        #expect(immediateHandlerCalls.value == 1)
    }

    @Test func `Shutdown stream finishes without values when token is canceled`() async {
        let token = ShutdownToken()
        var iterator = token.stream().makeAsyncIterator()

        token.cancel()

        let nextValue: Void? = await iterator.next()

        #expect(nextValue == nil)
    }

    @Test func `Shutdown stream from already canceled token finishes immediately without values`() async {
        let token = ShutdownToken()

        token.cancel()

        var iterator = token.stream().makeAsyncIterator()
        let nextValue: Void? = await iterator.next()

        #expect(nextValue == nil)
    }
}
