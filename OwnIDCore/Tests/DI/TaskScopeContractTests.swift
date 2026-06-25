import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct TaskScopeContractTests {

    @Test func `Shutdown token cancels tracked tasks and rejects future spawns`() async throws {
        let token = ShutdownToken()
        let scope = TaskScope(shutdownToken: token)
        let rejectedBodyRuns = LockedCounter()

        let task = try await confirmation("tracked task starts and receives cancellation", expectedCount: 2) { confirm in
            let task = try #require(
                scope.spawn(onCancel: {
                    confirm()
                }) {
                    confirm()
                    await waitForTaskCancellation()
                }
            )

            token.cancel()
            await task.value

            return task
        }

        await task.value
        #expect(
            scope.spawn {
                _ = rejectedBodyRuns.increment()
            } == nil
        )
        #expect(rejectedBodyRuns.value == 0)
    }

    @Test func `Shutdown handlers run once can be removed and run immediately after shutdown`() throws {
        let scope = TaskScope(shutdownToken: ShutdownToken())
        let retainedHandlerCalls = LockedCounter()
        let removedHandlerCalls = LockedCounter()
        let immediateHandlerCalls = LockedCounter()

        _ = try #require(
            scope.onShutdown {
                _ = retainedHandlerCalls.increment()
            }
        )
        let removedID = try #require(
            scope.onShutdown {
                _ = removedHandlerCalls.increment()
            }
        )

        scope.removeShutdownHandler(removedID)

        scope.shutdown()
        scope.shutdown()

        #expect(retainedHandlerCalls.value == 1)
        #expect(removedHandlerCalls.value == 0)

        let immediateID = scope.onShutdown {
            _ = immediateHandlerCalls.increment()
        }

        #expect(immediateID == nil)
        #expect(immediateHandlerCalls.value == 1)
    }
}
