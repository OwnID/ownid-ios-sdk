import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@MainActor
struct OperationRegistryImplContractTests {

    @Test func `Register and unregister maintain active controller snapshot`() throws {
        let registry = OperationRegistryImpl(logger: nil)
        let loginController = TestOperationController(type: .sessionCreation, id: "login")
        let collectController = TestOperationController(type: .loginIDCollect, id: "collect")

        registry.register(controller: loginController)
        registry.register(controller: collectController)

        try assertSnapshot(registry.operations, containsExactly: [loginController, collectController])

        registry.unregister(id: loginController.operationID)

        try assertSnapshot(registry.operations, containsExactly: [collectController])

        registry.unregister(id: collectController.operationID)

        #expect(registry.operations.isEmpty)
    }

    @Test func `Current stream yields latest snapshot to new subscribers`() async throws {
        let registry = OperationRegistryImpl(logger: nil)
        let controller = TestOperationController(type: .passkeyAuth, id: "active")
        registry.register(controller: controller)
        var iterator = registry.current.makeAsyncIterator()

        let snapshot = try requireState(await iterator.next())

        try assertSnapshot(snapshot.map, containsExactly: [controller])
    }

    @Test func `Current stream publishes full replacement states after mutations`() async throws {
        let registry = OperationRegistryImpl(logger: nil)
        let first = TestOperationController(type: .emailVerification, id: "first")
        let second = TestOperationController(type: .phoneNumberVerification, id: "second")
        var iterator = registry.current.makeAsyncIterator()

        try assertSnapshot((try requireState(await iterator.next())).map, containsExactly: [])

        registry.register(controller: first)
        try assertSnapshot((try requireState(await iterator.next())).map, containsExactly: [first])

        registry.register(controller: second)
        try assertSnapshot((try requireState(await iterator.next())).map, containsExactly: [first, second])

        registry.unregister(id: first.operationID)
        try assertSnapshot((try requireState(await iterator.next())).map, containsExactly: [second])
    }

    private func requireState(
        _ state: OperationRegistryState?,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) throws -> OperationRegistryState {
        return try #require(state, "Expected OperationRegistry.current to yield state.", sourceLocation: sourceLocation)
    }
}

private func assertSnapshot(
    _ snapshot: [OperationID: any OperationController]?,
    containsExactly expectedControllers: [TestOperationController],
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    let snapshot = try #require(snapshot, sourceLocation: sourceLocation)
    let expectedIDs = Set(expectedControllers.map(\.operationID))

    #expect(Set(snapshot.keys) == expectedIDs, sourceLocation: sourceLocation)

    for controller in expectedControllers {
        let storedController = try #require(snapshot[controller.operationID] as? TestOperationController, sourceLocation: sourceLocation)
        #expect(storedController === controller, sourceLocation: sourceLocation)
    }
}

private final class TestOperationController: OperationController, @unchecked Sendable {
    typealias Success = Void
    typealias Failure = TestOperationFailure

    let operationID: OperationID

    init(type: OperationType, id: String) {
        operationID = OperationID(type: type, id: id)
    }

    func abort(reason: Reason) {}

    func whenSettled() async -> OperationResult<Void, TestOperationFailure> {
        .canceled(.userClose())
    }
}

private struct TestOperationFailure: OperationFailure {
    let errorCode: ErrorCode = .unknown
    let message = "test failure"
}
