import Foundation
import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@Suite(.serialized)
struct OwnIDOperationUIHostingContractTests {

    @Test func `App hosted entry preserves operation params and replaces SDK UI container`() async throws {
        let recorder = AppHostedLoginIDCollectRecorder()
        let parentContainer = DIContainerImpl(scopeName: "operation-ui-hosting-parent")
        parentContainer.register(InstanceName.self, instance: InstanceName(value: "operation-ui-hosting"))
        parentContainer.register(
            (any OperationUIContainer).self,
            instance: SentinelOperationUIContainer() as any OperationUIContainer
        )
        parentContainer.registerFactory((any LoginIDCollectOperation).self, dependencies: []) { resolver in
            AppHostedLoginIDCollectOperation(resolver: resolver, recorder: recorder)
        }

        let sourceEntry = scopedLoginIDCollectEntry(container: parentContainer)
        let sourceAvailability = await sourceEntry.availability(
            params: LoginIDCollectOperationParams(loginID: LoginID(id: "source@example.test", type: .email))
        )

        let hostedEntry = sourceEntry.useAppHostedComponent
        let hostedAvailability = await hostedEntry.availability(
            params: LoginIDCollectOperationParams(loginID: LoginID(id: "available@example.test", type: .email))
        )
        _ = hostedEntry.start(
            params: LoginIDCollectOperationParams(loginID: LoginID(id: "start@example.test", type: .email))
        )

        try requireAvailable(sourceAvailability)
        try requireAvailable(hostedAvailability)
        #expect(hostedEntry.operationType == .loginIDCollect)
        #expect(
            recorder.snapshot()
                == AppHostedLoginIDCollectSnapshot(
                    scopeNames: [
                        "operation-ui-hosting-parent",
                        "OperationUIHosting.\(OperationType.loginIDCollect.rawValue)",
                        "OperationUIHosting.\(OperationType.loginIDCollect.rawValue)",
                    ],
                    uiContainerSources: ["parent", "override", "override"],
                    availabilityLoginIDs: ["source@example.test", "available@example.test"],
                    startLoginIDs: ["start@example.test"]
                )
        )
    }

    @Test func `Operation UI controller delegates identity settlement and abort`() async throws {
        let delegate = ManualLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "delegated"))
        let controller = OwnIDOperationUIController(
            instanceName: InstanceName(value: "operation-ui-controller"),
            delegate: delegate
        )

        controller.abort(reason: .systemError(details: "owner stopped"))
        await delegate.settle(.success(LoginID(id: "settled@example.test", type: .email)))

        #expect(controller.operationID == OperationID(type: .loginIDCollect, id: "delegated"))
        #expect(try requireSuccess(await controller.whenSettled()) == LoginID(id: "settled@example.test", type: .email))
        #expect(delegate.abortDescriptions() == [Reason.systemError(details: "owner stopped").description])
    }

    @MainActor
    @Test func `Lifecycle session cancels unsettled app hosted operation when container closes`() {
        let controller = ManualLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "unsettled-close"))
        let containerController = OwnIDUIContainerController(closeAction: {})
        let session = OperationLifecycleSession(operationController: controller, usesAppContainer: true)

        session.activate(containerController: containerController, onSettled: {})
        containerController.markOpened()
        containerController.close()
        containerController.markClosed()

        #expect(controller.abortDescriptions() == [Reason.userClose(details: "Operation container closed").description])
    }

    @MainActor
    @Test func `Lifecycle session dismisses settled app hosted operation without later cancellation`() async throws {
        var closeActionCount = 0
        let settledSignal = MainActorSignal()
        let controller = ManualLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "settled-close"))
        let containerController = OwnIDUIContainerController {
            closeActionCount += 1
        }
        let session = OperationLifecycleSession(operationController: controller, usesAppContainer: true)

        session.activate(
            containerController: containerController,
            onSettled: {
                settledSignal.signal()
            }
        )
        containerController.markOpened()
        await controller.settle(.success(LoginID(id: "settled@example.test", type: .email)))
        await settledSignal.wait()
        containerController.markClosed()

        #expect(closeActionCount == 1)
        #expect(containerController.isClosed)
        #expect(controller.abortDescriptions().isEmpty)
    }

    @MainActor
    @Test func `App hosted view aborts and dismisses when strings provider is missing`() async throws {
        let controller = SettlingLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "missing-strings"))
        let closeSignal = MainActorSignal()
        let containerController = OwnIDUIContainerController {
            closeSignal.signal()
        }
        let resolver = DIContainerImpl(scopeName: "operation-ui-hosting-missing-strings")
        let host = SwiftUIRuntimeHost(
            rootView: OperationLifecycleHost(
                instanceResolver: resolver,
                operationController: controller,
                renderController: controller,
                containerController: containerController
            )
        )
        defer { host.close() }

        await host.settle()
        _ = await controller.whenSettled()
        await closeSignal.wait()
        containerController.markClosed()

        #expect(
            controller.abortDescriptions() == [
                Reason.systemError(details: "Missing strings provider for \(OperationType.loginIDCollect)").description
            ]
        )
        #expect(containerController.isClosed)
    }

    @MainActor
    @Test func `App hosted view aborts and dismisses when UI provider is missing`() async throws {
        let controller = SettlingLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "missing-provider"))
        let closeSignal = MainActorSignal()
        let containerController = OwnIDUIContainerController {
            closeSignal.signal()
        }
        let resolver = DIContainerImpl(scopeName: "operation-ui-hosting-missing-provider")
        resolver.register(
            (any LoginIDCollectStringsProvider).self,
            instance: StaticLoginIDCollectStringsProvider() as any LoginIDCollectStringsProvider
        )
        let host = SwiftUIRuntimeHost(
            rootView: OperationLifecycleHost(
                instanceResolver: resolver,
                operationController: controller,
                renderController: controller,
                containerController: containerController
            )
        )
        defer { host.close() }

        await host.settle()
        _ = await controller.whenSettled()
        await closeSignal.wait()
        containerController.markClosed()

        #expect(
            controller.abortDescriptions() == [
                Reason.systemError(details: "Missing UI provider for \(OperationType.loginIDCollect)").description
            ]
        )
        #expect(containerController.isClosed)
    }

    @MainActor
    @Test func `App hosted view aborts and dismisses when instance disappears`() async throws {
        let controller = SettlingLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "missing-instance"))
        let closeSignal = MainActorSignal()
        let containerController = OwnIDUIContainerController {
            closeSignal.signal()
        }
        let operationUIController = OwnIDOperationUIController<LoginID, LoginIDCollectOperationFailure>(
            instanceName: InstanceName(value: "missing-instance-\(UUID().uuidString)"),
            delegate: controller
        )
        let host = SwiftUIRuntimeHost(
            rootView: OwnIDOperationView(
                operationUIController: operationUIController,
                containerController: containerController
            )
        )
        defer { host.close() }

        await host.settle()
        _ = await controller.whenSettled()
        await closeSignal.wait()
        containerController.markClosed()

        #expect(
            controller.abortDescriptions() == [
                Reason.systemError(details: "OwnID SDK instance is no longer available").description
            ]
        )
        #expect(containerController.isClosed)
    }

    @MainActor
    @Test func `App hosted operation content uses host theme instead of registered SDK theme store`() async throws {
        let hostTheme = OwnIDTheme.capture(colorScheme: .light, primary: .green, onPrimary: .black)
        let sdkPresentedTheme = OwnIDTheme.capture(colorScheme: .dark, primary: .red, onPrimary: .white)
        let themeStore = OwnIDThemeStore()
        themeStore.set(sdkPresentedTheme)

        let recorder = AppHostedLoginIDCollectContentRecorder()
        let controller = RecordingLoginIDCollectOperationController(
            operationID: OperationID(type: .loginIDCollect, id: "host-theme"),
            uiState: testLoginIDCollectUIState(loginIDValue: "theme@example.test")
        )
        let resolver = loginIDCollectContentResolver(
            scopeName: "operation-ui-hosting-host-theme",
            recorder: recorder
        )
        resolver.register(OwnIDThemeStore.self, instance: themeStore)

        let containerController = OwnIDUIContainerController()
        containerController.markOpened()
        let host = SwiftUIRuntimeHost(
            rootView: OperationLifecycleHost(
                instanceResolver: resolver,
                operationController: controller,
                renderController: controller,
                containerController: containerController
            )
            .environment(\.ownIDTheme, hostTheme)
        )
        defer { host.close() }

        let snapshot = try await recorder.waitForSnapshot(
            matching: { $0.source == .provider && $0.theme == hostTheme },
            host: host
        )

        #expect(snapshot.theme == hostTheme)
        #expect(snapshot.theme != sdkPresentedTheme)
        #expect(recorder.snapshots().map(\.theme).contains(sdkPresentedTheme) == false)
    }

    @MainActor
    @Test func `Public app hosted operation view applies explicit theme to operation content`() async throws {
        let instanceName = InstanceName(value: "operation-ui-public-theme-\(UUID().uuidString)")
        defer { OwnID.destroy(instanceName: instanceName) }

        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = "OperationUITheme\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        }

        let explicitTheme = OwnIDTheme.capture(colorScheme: .light, primary: .green, onPrimary: .black)
        let sdkPresentedTheme = OwnIDTheme.capture(colorScheme: .dark, primary: .red, onPrimary: .white)
        let recorder = AppHostedLoginIDCollectContentRecorder()
        let controller = RecordingLoginIDCollectOperationController(
            operationID: OperationID(type: .loginIDCollect, id: "public-explicit-theme"),
            uiState: testLoginIDCollectUIState(loginIDValue: "public-theme@example.test")
        )
        let operationUIController = OwnIDOperationUIController<LoginID, LoginIDCollectOperationFailure>(
            instanceName: instanceName,
            delegate: controller
        )
        let container = try #require(OwnID.getInstanceContainer(instanceName))
        registerLoginIDCollectContent(in: container, recorder: recorder)
        try #require(container.getOrNil(type: OwnIDThemeStore.self)).set(sdkPresentedTheme)

        let host = SwiftUIRuntimeHost(
            rootView: OwnIDOperationView(
                operationUIController: operationUIController,
                theme: explicitTheme
            )
        )
        defer { host.close() }

        let snapshot = try await recorder.waitForSnapshot(
            matching: { $0.source == .provider && $0.theme == explicitTheme },
            host: host
        )

        #expect(snapshot.loginIDValue == "public-theme@example.test")
        #expect(snapshot.stringsTitle == "App-hosted title")
        #expect(snapshot.theme == explicitTheme)
        #expect(snapshot.theme != sdkPresentedTheme)
        #expect(recorder.snapshots().map(\.theme).contains(sdkPresentedTheme) == false)
    }

    @MainActor
    @Test func `App hosted operation override receives state strings error provider and focus readiness before registered provider`()
        async throws
    {
        let providerRecorder = AppHostedLoginIDCollectContentRecorder()
        let overrideRecorder = AppHostedLoginIDCollectContentRecorder()
        let controller = RecordingLoginIDCollectOperationController(
            operationID: OperationID(type: .loginIDCollect, id: "override-precedence"),
            uiState: testLoginIDCollectUIState(
                loginIDValue: "override@example.test",
                error: UIError(errorCode: .invalidArgument, localizedMessage: "Original error")
            )
        )
        let containerController = OwnIDUIContainerController()
        let resolver = loginIDCollectContentResolver(
            scopeName: "operation-ui-hosting-override-precedence",
            recorder: providerRecorder
        )

        let host = SwiftUIRuntimeHost(
            rootView: OperationLifecycleHost(
                instanceResolver: resolver,
                operationController: controller,
                renderController: controller,
                containerController: containerController,
                errorTextProvider: { "mapped-\($0.rawValue)" }
            )
            .withLoginIDCollectContent { state, strings, errorTextProvider, isReadyForInitialFocus in
                AppHostedLoginIDCollectContentProbe(
                    source: .override,
                    recorder: overrideRecorder,
                    uiState: state,
                    strings: strings,
                    errorTextProvider: errorTextProvider,
                    isReadyForInitialFocus: isReadyForInitialFocus
                )
            }
        )
        defer { host.close() }

        let notReady = try await overrideRecorder.waitForSnapshot(
            matching: { $0.source == .override && $0.isReadyForInitialFocus == false },
            host: host
        )

        containerController.markOpened()

        let ready = try await overrideRecorder.waitForSnapshot(
            matching: { $0.source == .override && $0.isReadyForInitialFocus == true },
            host: host
        )

        #expect(notReady.loginIDValue == "override@example.test")
        #expect(notReady.stringsTitle == "App-hosted title")
        #expect(notReady.errorCode == .invalidArgument)
        #expect(notReady.errorText == "mapped-invalid_argument")
        #expect(ready.loginIDValue == "override@example.test")
        #expect(ready.stringsTitle == "App-hosted title")
        #expect(ready.errorText == "mapped-invalid_argument")
        #expect(providerRecorder.snapshots().isEmpty)
    }

    @MainActor
    @Test func `App hosted operation content falls back to registered provider when override is unset`() async throws {
        let providerRecorder = AppHostedLoginIDCollectContentRecorder()
        let controller = RecordingLoginIDCollectOperationController(
            operationID: OperationID(type: .loginIDCollect, id: "provider-fallback"),
            uiState: testLoginIDCollectUIState(
                loginIDValue: "provider@example.test",
                error: UIError(errorCode: .network, localizedMessage: "Network error")
            )
        )
        let resolver = loginIDCollectContentResolver(
            scopeName: "operation-ui-hosting-provider-fallback",
            recorder: providerRecorder
        )
        let containerController = OwnIDUIContainerController()
        containerController.markOpened()
        let host = SwiftUIRuntimeHost(
            rootView: OperationLifecycleHost(
                instanceResolver: resolver,
                operationController: controller,
                renderController: controller,
                containerController: containerController,
                errorTextProvider: { "fallback-\($0.rawValue)" }
            )
        )
        defer { host.close() }

        let snapshot = try await providerRecorder.waitForSnapshot(
            matching: { $0.source == .provider && $0.isReadyForInitialFocus == true },
            host: host
        )

        #expect(snapshot.loginIDValue == "provider@example.test")
        #expect(snapshot.stringsTitle == "App-hosted title")
        #expect(snapshot.errorCode == .network)
        #expect(snapshot.errorText == "fallback-network")
    }
}

private func scopedLoginIDCollectEntry(
    container: any DIContainer
) -> any OperationEntry<LoginIDCollectOperationParams?, LoginID, LoginIDCollectOperationFailure> {
    scopedOperationEntry(
        container: container,
        runtimeType: (any LoginIDCollectOperation).self,
        operationType: .loginIDCollect,
        availability: { runtime, params in await runtime.availability(params: params) },
        start: { runtime, params in runtime.start(params: params) }
    )
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

private func requireSuccess(
    _ result: OperationResult<LoginID, LoginIDCollectOperationFailure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> LoginID {
    switch result {
    case .success(let loginID):
        return loginID
    case .canceled(let reason):
        return try #require(nil as LoginID?, "Expected success, got cancellation: \(reason)", sourceLocation: sourceLocation)
    case .failure(let failure):
        return try #require(nil as LoginID?, "Expected success, got failure: \(failure)", sourceLocation: sourceLocation)
    }
}

private func loginIDCollectContentResolver(
    scopeName: String,
    recorder: AppHostedLoginIDCollectContentRecorder
) -> DIContainerImpl {
    let resolver = DIContainerImpl(scopeName: scopeName)
    registerLoginIDCollectContent(in: resolver, recorder: recorder)
    return resolver
}

private func registerLoginIDCollectContent(
    in container: any DIContainer,
    recorder: AppHostedLoginIDCollectContentRecorder
) {
    container.register(
        (any LoginIDCollectStringsProvider).self,
        instance: AppHostedLoginIDCollectStringsProvider() as any LoginIDCollectStringsProvider
    )
    container.register(
        (any LoginIDCollectUIProvider).self,
        instance: RecordingLoginIDCollectUIProvider(recorder: recorder) as any LoginIDCollectUIProvider
    )
}

private func testLoginIDCollectUIState(
    loginIDValue: String,
    error: UIError? = nil
) -> LoginIDCollectUIState {
    LoginIDCollectUIState(
        loginIDValue: loginIDValue,
        collectableLoginIDTypes: [.email],
        error: error,
        onLoginIDChange: { _ in },
        onContinue: {},
        onCancel: {}
    )
}

private final class AppHostedLoginIDCollectOperation: LoginIDCollectOperation, @unchecked Sendable {
    let operationType: OperationType = .loginIDCollect

    private let recorder: AppHostedLoginIDCollectRecorder

    init(resolver: any DIContainerResolver, recorder: AppHostedLoginIDCollectRecorder) {
        self.recorder = recorder
        recorder.recordRuntime(scopeName: resolver.scopeName, uiContainerSource: uiContainerSource(from: resolver))
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        recorder.recordAvailability(loginID(from: params))
        return .available
    }

    func start(params: LoginIDCollectOperationParams?) -> any OperationController<LoginID, LoginIDCollectOperationFailure> {
        recorder.recordStart(params?.loginID?.id ?? "<nil>")
        return ManualLoginIDCollectOperationController(operationID: OperationID(type: .loginIDCollect, id: "app-hosted"))
    }

    private func uiContainerSource(from resolver: any DIContainerResolver) -> String {
        guard let container = resolver.getOrNil(type: (any OperationUIContainer).self) else { return "missing" }
        return container is SentinelOperationUIContainer ? "parent" : "override"
    }

    private func loginID(from params: (any CapabilityParams)?) -> String {
        (params as? LoginIDCollectOperationParams)?.loginID?.id ?? "<nil>"
    }
}

private final class RecordingLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID: OperationID

    private let uiState: LoginIDCollectUIState
    private let settlement = CancellablePendingValue(
        OperationResult<LoginID, LoginIDCollectOperationFailure>.canceled(.timeout)
    )

    init(operationID: OperationID, uiState: LoginIDCollectUIState) {
        self.operationID = operationID
        self.uiState = uiState
    }

    func abort(reason: Reason) {}

    func whenSettled() async -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        await settlement.wait()
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        AsyncStream { continuation in
            continuation.yield(.active(uiState: uiState))
        }
    }
}

private final class ManualLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID: OperationID

    private let aborts = LockedValue<[String]>([])
    private let store = ManualOperationResultStore<LoginID, LoginIDCollectOperationFailure>()

    init(operationID: OperationID) {
        self.operationID = operationID
    }

    func abort(reason: Reason) {
        aborts.mutate { $0.append(reason.description) }
    }

    func whenSettled() async -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        await store.wait()
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        AsyncStream { continuation in continuation.finish() }
    }

    func settle(_ result: OperationResult<LoginID, LoginIDCollectOperationFailure>) async {
        await store.resolve(result)
    }

    func abortDescriptions() -> [String] {
        aborts.get()
    }
}

private final class SettlingLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID: OperationID

    private let aborts = LockedValue<[String]>([])
    private let store = ManualOperationResultStore<LoginID, LoginIDCollectOperationFailure>()

    init(operationID: OperationID) {
        self.operationID = operationID
    }

    func abort(reason: Reason) {
        aborts.mutate { $0.append(reason.description) }
        Task { await store.resolve(.canceled(reason)) }
    }

    func whenSettled() async -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        await store.wait()
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        AsyncStream { continuation in
            continuation.yield(
                .active(
                    uiState: LoginIDCollectUIState(
                        loginIDValue: "",
                        collectableLoginIDTypes: [.email],
                        onLoginIDChange: { _ in },
                        onContinue: {},
                        onCancel: {}
                    )
                )
            )
        }
    }

    func abortDescriptions() -> [String] {
        aborts.get()
    }
}

private struct StaticLoginIDCollectStringsProvider: LoginIDCollectStringsProvider {
    func getStrings(params: LoginIDCollectStringsParams) -> AsyncStream<LoginIDCollectStrings?> {
        AsyncStream { continuation in
            continuation.yield(.default(loginIDTypes: [.email], isSystemFidoCapable: true))
        }
    }
}

private struct AppHostedLoginIDCollectStringsProvider: LoginIDCollectStringsProvider {
    func getStrings(params: LoginIDCollectStringsParams) -> AsyncStream<LoginIDCollectStrings?> {
        AsyncStream { continuation in
            continuation.yield(
                LoginIDCollectStrings(
                    title: "App-hosted title",
                    message: "App-hosted message",
                    placeholder: "App-hosted placeholder",
                    cancel: "App-hosted cancel",
                    cta: "App-hosted continue",
                    error: "App-hosted error"
                )
            )
        }
    }
}

private struct RecordingLoginIDCollectUIProvider: LoginIDCollectUIProvider, @unchecked Sendable {
    let recorder: AppHostedLoginIDCollectContentRecorder

    @MainActor
    func content(
        uiState: LoginIDCollectUIState,
        uiStrings: LoginIDCollectStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView {
        AnyView(
            AppHostedLoginIDCollectContentProbe(
                source: .provider,
                recorder: recorder,
                uiState: uiState,
                strings: uiStrings,
                errorTextProvider: errorTextProvider,
                isReadyForInitialFocus: isReadyForInitialFocus
            )
        )
    }
}

private struct AppHostedLoginIDCollectContentProbe: View {
    @Environment(\.ownIDTheme) private var theme

    let source: AppHostedLoginIDCollectContentSource
    let recorder: AppHostedLoginIDCollectContentRecorder
    let uiState: LoginIDCollectUIState
    let strings: LoginIDCollectStrings
    let errorTextProvider: ((ErrorCode) -> String)?
    let isReadyForInitialFocus: Bool

    var body: some View {
        RuntimeSnapshotProbe(
            snapshot: AppHostedLoginIDCollectContentSnapshot(
                source: source,
                loginIDValue: uiState.loginIDValue,
                stringsTitle: strings.title,
                errorCode: uiState.error?.errorCode,
                errorText: uiState.error.map { errorTextProvider?($0.errorCode) ?? $0.localizedMessage },
                isReadyForInitialFocus: isReadyForInitialFocus,
                theme: theme
            ),
            recorder: recorder
        )
        .frame(width: 1, height: 1)
    }
}

private typealias AppHostedLoginIDCollectContentRecorder = RuntimeSnapshotRecorder<AppHostedLoginIDCollectContentSnapshot>

private enum AppHostedLoginIDCollectContentSource: Equatable, Sendable {
    case provider
    case override
}

private struct AppHostedLoginIDCollectContentSnapshot: Equatable, Sendable {
    let source: AppHostedLoginIDCollectContentSource
    let loginIDValue: String
    let stringsTitle: String
    let errorCode: ErrorCode?
    let errorText: String?
    let isReadyForInitialFocus: Bool
    let theme: OwnIDTheme?
}

private actor ManualOperationResultStore<Success: Sendable, Failure: OperationFailure> {
    private var result: OperationResult<Success, Failure>?
    private var waiters: [CheckedContinuation<OperationResult<Success, Failure>, Never>] = []

    func wait() async -> OperationResult<Success, Failure> {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func resolve(_ result: OperationResult<Success, Failure>) {
        guard self.result == nil else { return }
        self.result = result
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }
}

@MainActor
private final class MainActorSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        signaled = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class SentinelOperationUIContainer: OperationUIContainer, @unchecked Sendable {
    @MainActor func show<Controller: OperationController>(controller: Controller) {}
}

private final class AppHostedLoginIDCollectRecorder: @unchecked Sendable {
    private let values = LockedValue(
        AppHostedLoginIDCollectSnapshot(
            scopeNames: [],
            uiContainerSources: [],
            availabilityLoginIDs: [],
            startLoginIDs: []
        )
    )

    func recordRuntime(scopeName: String, uiContainerSource: String) {
        values.mutate {
            $0.scopeNames.append(scopeName)
            $0.uiContainerSources.append(uiContainerSource)
        }
    }

    func recordAvailability(_ loginID: String) {
        values.mutate { $0.availabilityLoginIDs.append(loginID) }
    }

    func recordStart(_ loginID: String) {
        values.mutate { $0.startLoginIDs.append(loginID) }
    }

    func snapshot() -> AppHostedLoginIDCollectSnapshot {
        values.get()
    }
}

private struct AppHostedLoginIDCollectSnapshot: Equatable, Sendable {
    var scopeNames: [String]
    var uiContainerSources: [String]
    var availabilityLoginIDs: [String]
    var startLoginIDs: [String]
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    @discardableResult
    func mutate<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&value) }
    }
}
