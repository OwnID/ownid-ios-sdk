import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct OperationInfrastructureContractTests {

    @Test func `Availability preflight resolves runtime but does not start operation`() async throws {
        let recorder = OperationEntryRecorder()
        let entry = makeOperationEntry(recorder: recorder)

        let availability = await entry.availability(params: TestOperationParams(value: "preflight"))

        try requireAvailable(availability)
        let snapshot = recorder.snapshot()
        #expect(snapshot.factoryCount == 1)
        #expect(snapshot.availabilityParams == ["preflight"])
        #expect(snapshot.startParams.isEmpty)
        #expect(snapshot.controllerRuntimeIDs.isEmpty)
    }

    @Test func `Start resolves runtime and returns caller owned controller`() throws {
        let recorder = OperationEntryRecorder()
        let entry = makeOperationEntry(recorder: recorder)

        let controller = try #require(entry.start(params: TestOperationParams(value: "launch")) as? RecordingOperationController)

        #expect(controller.operationID.type == .sessionCreation)
        #expect(controller.runtimeID == 1)
        #expect(controller.scopeMarker == nil)
        let snapshot = recorder.snapshot()
        #expect(snapshot.factoryCount == 1)
        #expect(snapshot.startParams == ["launch"])
        #expect(snapshot.controllerRuntimeIDs == [1])
    }

    @Test func `Controller settlement is stored once`() async throws {
        let aborts = AbortRecorder()
        let controller = OperationControllerImpl<String, TestOperationFailure>(
            operationID: OperationID(type: .loginIDCollect, id: "settle-once"),
            onUserAborted: { aborts.record($0) }
        )

        controller.complete("first")
        let first = try await successValue(controller.whenSettled())

        controller.fail(TestOperationFailure(message: "late failure"))
        controller.cancel(.timeout)

        let second = try await successValue(controller.whenSettled())
        #expect(first == "first")
        #expect(second == "first")
        #expect(aborts.reasons().isEmpty)
    }

    @Test func `Multiple and late awaiters receive cached terminal result`() async throws {
        let controller = OperationControllerImpl<String, TestOperationFailure>(
            operationID: OperationID(type: .passkeyAuth, id: "cached-awaiters"),
            onUserAborted: { _ in }
        )

        let first = Task { await controller.whenSettled() }
        let second = Task { await controller.whenSettled() }

        controller.complete("cached")

        let firstValue = try await successValue(first.value)
        let secondValue = try await successValue(second.value)
        let lateValue = try await successValue(controller.whenSettled())

        #expect(firstValue == "cached")
        #expect(secondValue == "cached")
        #expect(lateValue == "cached")
    }

    @Test func `Canceling awaiting task does not abort or prevent operation settlement`() async throws {
        let aborts = AbortRecorder()
        let controller = OperationControllerImpl<String, TestOperationFailure>(
            operationID: OperationID(type: .emailVerification, id: "awaiter-cancel"),
            onUserAborted: { aborts.record($0) }
        )
        let gate = AwaiterGate()

        let waiter = Task {
            await gate.markStarted()
            return await controller.whenSettled()
        }

        await gate.waitUntilStarted()
        waiter.cancel()
        controller.complete("still-running")

        let value = try await successValue(waiter.value)
        #expect(value == "still-running")
        #expect(aborts.reasons().isEmpty)
    }

    @Test func `Entry factory starts use fresh runtimes while instance runtime can reuse controller`() throws {
        let recorder = OperationEntryRecorder()
        let factoryEntry = makeOperationEntry(recorder: recorder)

        let firstFactoryController = try #require(factoryEntry.start(params: nil) as? RecordingOperationController)
        let secondFactoryController = try #require(factoryEntry.start(params: nil) as? RecordingOperationController)

        #expect(firstFactoryController !== secondFactoryController)
        #expect(firstFactoryController.runtimeID == 1)
        #expect(secondFactoryController.runtimeID == 2)
        #expect(recorder.snapshot().factoryCount == 2)

        let instanceContainer = DIContainerImpl(scopeName: "operation-infrastructure-instance")
        let instanceRecorder = OperationEntryRecorder()
        let runtime = RecordingOperationRuntime(
            runtimeID: 1,
            scopeMarker: nil,
            recorder: instanceRecorder
        )
        instanceContainer.register((any TestOperationRuntime).self, instance: runtime)
        let instanceEntry = makeOperationEntry(container: instanceContainer)

        let firstInstanceController = try #require(instanceEntry.start(params: nil) as? RecordingOperationController)
        let secondInstanceController = try #require(instanceEntry.start(params: nil) as? RecordingOperationController)

        #expect(firstInstanceController === secondInstanceController)
        #expect(instanceRecorder.snapshot().startParams == ["<nil>", "<nil>"])
        #expect(instanceRecorder.snapshot().controllerRuntimeIDs == [1])
    }

    @Test func `Scoped entries create operation local scope while plain entries use bound scope`() throws {
        let plainRecorder = OperationEntryRecorder()
        let scopedRecorder = OperationEntryRecorder()
        let plainContainer = makeContainer(
            scopeName: "operation-infrastructure-plain",
            recorder: plainRecorder,
            marker: ScopeMarker(value: "plain-parent")
        )
        let scopedContainer = makeContainer(
            scopeName: "operation-infrastructure-scoped",
            recorder: scopedRecorder,
            marker: ScopeMarker(value: "scoped-parent")
        )

        let plainEntry = makeOperationEntry(container: plainContainer)
        let scopedEntry = makeScopedOperationEntry(container: scopedContainer)

        #expect((plainEntry as? any ScopedOperationEntry) == nil)

        let plainController = try #require(plainEntry.start(params: nil) as? RecordingOperationController)
        #expect(plainController.scopeMarker?.value == "plain-parent")

        let scoped = try #require(scopedEntry as? any ScopedOperationEntry)
        #expect(scoped.instanceName == InstanceName(value: "OperationInfrastructureContractTests"))
        let childAny = scoped.withOperationScope("operation-child") { container in
            container.register(ScopeMarker.self, instance: ScopeMarker(value: "operation-child"))
        }
        let childEntry = try #require(childAny as? AnyScopedOperationEntry<TestOperationParams?, String, TestOperationFailure>)
        let childController = try #require(childEntry.start(params: nil) as? RecordingOperationController)
        let parentController = try #require(scopedEntry.start(params: nil) as? RecordingOperationController)

        #expect(childController.scopeMarker?.value == "operation-child")
        #expect(parentController.scopeMarker?.value == "scoped-parent")
    }
}

private func makeOperationEntry(
    recorder: OperationEntryRecorder = OperationEntryRecorder()
) -> any OperationEntry<TestOperationParams?, String, TestOperationFailure> {
    makeOperationEntry(container: makeContainer(scopeName: "OperationInfrastructureContractTests", recorder: recorder, marker: nil))
}

private func makeOperationEntry(
    container: any DIContainer
) -> any OperationEntry<TestOperationParams?, String, TestOperationFailure> {
    operationEntry(
        container: container,
        runtimeType: (any TestOperationRuntime).self,
        operationType: .sessionCreation,
        availability: { runtime, params in await runtime.availability(params: params) },
        start: { runtime, params in runtime.start(params: params) }
    )
}

private func makeScopedOperationEntry(
    container: any DIContainer
) -> any OperationEntry<TestOperationParams?, String, TestOperationFailure> {
    scopedOperationEntry(
        container: container,
        runtimeType: (any TestOperationRuntime).self,
        operationType: .sessionCreation,
        availability: { runtime, params in await runtime.availability(params: params) },
        start: { runtime, params in runtime.start(params: params) }
    )
}

private func makeContainer(
    scopeName: String,
    recorder: OperationEntryRecorder,
    marker: ScopeMarker?
) -> DIContainerImpl {
    let container = DIContainerImpl(scopeName: scopeName)
    if let marker {
        container.register(ScopeMarker.self, instance: marker)
    }
    container.register(InstanceName.self, instance: InstanceName(value: "OperationInfrastructureContractTests"))
    container.registerFactory((any TestOperationRuntime).self, dependencies: []) { resolver -> any TestOperationRuntime in
        let runtimeID = recorder.nextRuntimeID()
        let scopeMarker = resolver.getOrNil(type: ScopeMarker.self)
        return RecordingOperationRuntime(runtimeID: runtimeID, scopeMarker: scopeMarker, recorder: recorder)
    }
    return container
}

private func requireAvailable(
    _ availability: Availability,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws {
    switch availability {
    case .available:
        return
    case .unavailable(let message):
        try #require(nil as Void?, "Expected available, got unavailable: \(message)", sourceLocation: sourceLocation)
    }
}

private func successValue(
    _ result: OperationResult<String, TestOperationFailure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> String {
    switch result {
    case .success(let value):
        return value
    case .canceled(let reason):
        return try #require(nil as String?, "Expected success, got canceled: \(reason)", sourceLocation: sourceLocation)
    case .failure(let failure):
        return try #require(nil as String?, "Expected success, got failure: \(failure)", sourceLocation: sourceLocation)
    }
}

private protocol TestOperationRuntime: OperationCapability, AnyObject, Sendable
where Params == TestOperationParams, Result == String, Failure == TestOperationFailure {}

private final class RecordingOperationRuntime: TestOperationRuntime, @unchecked Sendable {
    let operationType: OperationType = .sessionCreation

    private let runtimeID: Int
    private let scopeMarker: ScopeMarker?
    private let recorder: OperationEntryRecorder
    private let lock = NSLock()
    private var controller: RecordingOperationController?

    init(runtimeID: Int, scopeMarker: ScopeMarker?, recorder: OperationEntryRecorder) {
        self.runtimeID = runtimeID
        self.scopeMarker = scopeMarker
        self.recorder = recorder
    }

    fileprivate func availability(params: (any CapabilityParams)?) async -> Availability {
        recorder.recordAvailability(paramValue(params))
        return .available
    }

    fileprivate func start(params: TestOperationParams?) -> any OperationController<String, TestOperationFailure> {
        recorder.recordStart(params?.value ?? "<nil>")
        lock.lock()
        defer { lock.unlock() }
        if let controller { return controller }
        let controller = RecordingOperationController(runtimeID: runtimeID, scopeMarker: scopeMarker)
        self.controller = controller
        recorder.recordController(runtimeID)
        return controller
    }
}

private final class RecordingOperationController: OperationController, @unchecked Sendable {
    typealias Success = String
    typealias Failure = TestOperationFailure

    let operationID: OperationID
    let runtimeID: Int
    let scopeMarker: ScopeMarker?

    init(runtimeID: Int, scopeMarker: ScopeMarker?) {
        self.runtimeID = runtimeID
        self.scopeMarker = scopeMarker
        self.operationID = OperationID(type: .sessionCreation, id: "runtime-\(runtimeID)")
    }

    fileprivate func abort(reason: Reason) {}

    fileprivate func whenSettled() async -> OperationResult<String, TestOperationFailure> {
        .success("runtime-\(runtimeID)")
    }
}

private final class OperationEntryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 0
    private var factories = 0
    private var availabilityValues: [String] = []
    private var startValues: [String] = []
    private var controllerIDs: [Int] = []

    func nextRuntimeID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        nextID += 1
        factories += 1
        return nextID
    }

    func recordAvailability(_ value: String) {
        lock.lock()
        availabilityValues.append(value)
        lock.unlock()
    }

    func recordStart(_ value: String) {
        lock.lock()
        startValues.append(value)
        lock.unlock()
    }

    func recordController(_ runtimeID: Int) {
        lock.lock()
        controllerIDs.append(runtimeID)
        lock.unlock()
    }

    func snapshot() -> OperationEntryRecorderSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return OperationEntryRecorderSnapshot(
            factoryCount: factories,
            availabilityParams: availabilityValues,
            startParams: startValues,
            controllerRuntimeIDs: controllerIDs
        )
    }
}

private struct OperationEntryRecorderSnapshot: Sendable {
    let factoryCount: Int
    let availabilityParams: [String]
    let startParams: [String]
    let controllerRuntimeIDs: [Int]
}

private final class AbortRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func record(_ reason: Reason) {
        lock.lock()
        values.append(reason.description)
        lock.unlock()
    }

    func reasons() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private actor AwaiterGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        started = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private struct TestOperationParams: CapabilityParams, Sendable {
    let value: String
}

private struct ScopeMarker: Sendable, Equatable {
    let value: String
}

private struct TestOperationFailure: OperationFailure {
    let errorCode: ErrorCode = .unknown
    let message: String
}

private func paramValue(_ params: (any CapabilityParams)?) -> String {
    (params as? TestOperationParams)?.value ?? "<nil>"
}
