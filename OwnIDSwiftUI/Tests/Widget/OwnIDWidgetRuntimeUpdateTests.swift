import Foundation
import SwiftUI
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
struct OwnIDWidgetRuntimeUpdateTests {
    private let widgetButtonTitle = "Continue with OwnID"

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Default login widget keeps owned view model and latest callback across mounted update`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-login")
        let controller = DeferredLoginController()
        let flow = RecordingBoostLoginFlow(controllers: [controller])
        try initializeDefaultWidgetInstance(instanceName: instanceName, loginFlow: flow)
        defer { OwnID.destroy(instanceName: instanceName) }

        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: nil,
                loginID: " first@example.test ",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("initial:\(response.loginID.id)")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        try expectWidgetContext(flow.context(at: 0), normalizedLoginID: "first@example.test")
        #expect(flow.startCount == 1)

        host.update(
            rootView: loginWidget(
                viewModel: nil,
                loginID: " second@example.test ",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("updated:\(response.loginID.id)")
                }
            )
        )
        await host.settle(cycles: 1)

        await controller.settle(.success(makeLoginResponse(id: "second@example.test")))

        #expect(await callbackProbe.next() == "updated:second@example.test")
        #expect(flow.startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Default create-passkey widget keeps owned completion and uses latest reset callback`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-create-passkey")
        let controller = DeferredCreatePasskeyController()
        let flow = RecordingBoostCreatePasskeyFlow(controllers: [controller])
        try initializeDefaultWidgetInstance(instanceName: instanceName, createPasskeyFlow: flow)
        defer { OwnID.destroy(instanceName: instanceName) }

        let buttonProbe = WidgetButtonProbe()
        let newPasskeyProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: "new@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record(response.loginID.id)
                },
                onReset: {
                    resetProbe.record("initial")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        try expectWidgetContext(flow.context(at: 0), normalizedLoginID: "new@example.test")
        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await newPasskeyProbe.next() == "new@example.test")

        host.update(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: "other@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("updated:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("updated")
                }
            )
        )
        await host.settle(cycles: 2)

        #expect(await resetProbe.next() == "updated")
        #expect(flow.startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Default create-passkey widget drops owned completion when SwiftUI identity changes`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-create-passkey-identity")
        let firstController = DeferredCreatePasskeyController()
        let secondController = DeferredCreatePasskeyController()
        let flow = RecordingBoostCreatePasskeyFlow(controllers: [firstController, secondController])
        try initializeDefaultWidgetInstance(instanceName: instanceName, createPasskeyFlow: flow)
        defer { OwnID.destroy(instanceName: instanceName) }

        let buttonProbe = WidgetButtonProbe()
        let newPasskeyProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: identifiedCreatePasskeyWidget(
                identity: "initial",
                viewModel: nil,
                loginID: "new@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record(response.loginID.id)
                },
                onReset: {
                    resetProbe.record("initial")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        await firstController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await newPasskeyProbe.next() == "new@example.test")

        host.update(
            rootView: identifiedCreatePasskeyWidget(
                identity: "replacement",
                viewModel: nil,
                loginID: "new@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("updated:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("replacement")
                }
            )
        )
        await host.settle(cycles: 2)

        #expect(resetProbe.isEmpty)

        let action = try #require(buttonProbe.latestAction, "Expected replacement widget action")
        action()

        try expectWidgetContext(flow.context(at: 1), normalizedLoginID: "new@example.test")
        #expect(flow.startCount == 2)

        await secondController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await newPasskeyProbe.next() == "updated:new@example.test")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Login widget mounted update keeps view model and uses latest success callback`() async throws {
        let controller = DeferredLoginController()
        var startCount = 0
        let viewModel = makeLoginViewModel { _ in
            startCount += 1
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: " first@example.test ",
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("initial:\(response.loginID.id)")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(startCount == 1)

        host.update(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: " second@example.test ",
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("updated:\(response.loginID.id)")
                }
            )
        )
        await host.settle(cycles: 1)

        await controller.settle(.success(makeLoginResponse(id: "second@example.test")))
        let callback = await callbackProbe.next()

        #expect(callback == "updated:second@example.test")
        #expect(startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Login widget callback-only update keeps active flow and uses latest success callback`() async throws {
        let controller = DeferredLoginController()
        var startCount = 0
        let viewModel = makeLoginViewModel { _ in
            startCount += 1
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("initial:\(response.loginID.id)")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(startCount == 1)

        host.update(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("updated:\(response.loginID.id)")
                }
            )
        )
        await host.settle(cycles: 1)

        await controller.settle(.success(makeLoginResponse(id: "user@example.test")))
        let callback = await callbackProbe.next()

        #expect(callback == "updated:user@example.test")
        #expect(startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Login widget reports busy disabled state and ignores repeated taps while running`() async throws {
        let controller = DeferredLoginController()
        var startCount = 0
        let viewModel = makeLoginViewModel { _ in
            startCount += 1
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record(response.loginID.id)
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        await host.settle(cycles: 1)

        let initialState = try #require(buttonProbe.latestState, "Expected initial widget button state")
        #expect(initialState == .ready(accessibilityLabel: widgetButtonTitle))

        let action = try #require(buttonProbe.latestAction, "Expected mounted widget action")
        action()
        action()
        await host.settle(cycles: 2)

        let runningState = try #require(buttonProbe.latestState, "Expected running widget button state")
        #expect(startCount == 1)
        #expect(runningState == .busy(accessibilityLabel: widgetButtonTitle))

        await controller.settle(.success(makeLoginResponse(id: "user@example.test")))
        #expect(await callbackProbe.next() == "user@example.test")
        await host.settle(cycles: 2)

        let settledState = try #require(buttonProbe.latestState, "Expected settled widget button state")
        #expect(settledState == .ready(accessibilityLabel: widgetButtonTitle))
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Create passkey widget mounted update keeps view model and uses latest new-passkey callback`() async throws {
        let controller = DeferredCreatePasskeyController()
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { _ in
            startCount += 1
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: " first@example.test ",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    callbackProbe.record("initial:\(response.loginID.id)")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(startCount == 1)

        host.update(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: " second@example.test ",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    callbackProbe.record("updated:\(response.loginID.id)")
                }
            )
        )
        await host.settle(cycles: 1)

        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "second@example.test"))))
        let callback = await callbackProbe.next()

        #expect(callback == "updated:second@example.test")
        #expect(startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Create passkey widget exposes completion checkmark after successful create-passkey result`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _ in controller }
        let buttonProbe = WidgetButtonProbe()
        let checkmarkProbe = WidgetCheckmarkProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "new@example.test",
                buttonProbe: buttonProbe,
                checkmarkProbe: checkmarkProbe,
                onNewPasskey: { response in
                    callbackProbe.record(response.loginID.id)
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))

        #expect(await callbackProbe.next() == "new@example.test")
        await host.settle(cycles: 3)

        let settledState = try #require(buttonProbe.latestState, "Expected settled create-passkey button state")
        #expect(settledState == .ready(accessibilityLabel: widgetButtonTitle))
        #expect(checkmarkProbe.didRender)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Create passkey widget mounted login ID update uses latest reset callback`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _ in controller }
        let buttonProbe = WidgetButtonProbe()
        let newPasskeyProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "new@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record(response.loginID.id)
                },
                onReset: {
                    resetProbe.record("initial")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await newPasskeyProbe.next() == "new@example.test")

        host.update(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "other@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("updated:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("updated")
                }
            )
        )
        await host.settle(cycles: 1)

        #expect(await resetProbe.next() == "updated")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Create passkey widget callback-only update keeps completion and updates later reset callback`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _ in controller }
        let buttonProbe = WidgetButtonProbe()
        let newPasskeyProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "new@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record(response.loginID.id)
                },
                onReset: {
                    resetProbe.record("initial")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await newPasskeyProbe.next() == "new@example.test")

        host.update(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "new@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("updated:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("callback-only")
                }
            )
        )
        await host.settle(cycles: 1)

        #expect(resetProbe.isEmpty)

        viewModel.onLoginIDChanged("other@example.test")

        #expect(await resetProbe.next() == "callback-only")
    }

    private func loginWidget(
        viewModel: OwnIDLoginWidgetViewModel?,
        loginID: String,
        instanceName: InstanceName = InstanceName(value: "widget-runtime-update"),
        buttonProbe: WidgetButtonProbe,
        onLogin: @escaping @MainActor (BoostFlowLoginResponse) -> Void
    ) -> some View {
        OwnIDLoginWidget(
            onLogin: onLogin,
            loginID: loginID,
            onError: { _ in },
            onCancel: { _ in },
            showSpinner: true,
            instanceName: instanceName,
            viewModel: viewModel,
            widgetStrings: BoostWidgetStrings(skipPassword: widgetButtonTitle, or: "or")
        )
        .iconButton { isBusy, isEnabled, action, accessibilityLabel in
            RecordingWidgetButton(
                isBusy: isBusy,
                isEnabled: isEnabled,
                action: action,
                accessibilityLabel: accessibilityLabel,
                probe: buttonProbe
            )
        }
        .frame(width: 180, height: 60)
    }

    private func createPasskeyWidget(
        viewModel: OwnIDCreatePasskeyWidgetViewModel?,
        loginID: String,
        instanceName: InstanceName = InstanceName(value: "widget-runtime-update"),
        buttonProbe: WidgetButtonProbe,
        checkmarkProbe: WidgetCheckmarkProbe? = nil,
        onNewPasskey: @escaping @MainActor (BoostFlowCreatePasskeyResponse) -> Void,
        onReset: @escaping @MainActor () -> Void = {}
    ) -> some View {
        OwnIDCreatePasskeyWidget(
            onLogin: { _ in },
            onNewPasskey: onNewPasskey,
            onReset: onReset,
            loginID: loginID,
            onError: { _ in },
            onCancel: { _ in },
            showSpinner: true,
            instanceName: instanceName,
            viewModel: viewModel,
            widgetStrings: BoostWidgetStrings(skipPassword: widgetButtonTitle, or: "or")
        )
        .iconButton { isBusy, isEnabled, action, accessibilityLabel in
            RecordingWidgetButton(
                isBusy: isBusy,
                isEnabled: isEnabled,
                action: action,
                accessibilityLabel: accessibilityLabel,
                probe: buttonProbe
            )
        }
        .checkmark {
            if let checkmarkProbe {
                RecordingWidgetCheckmark(probe: checkmarkProbe)
            } else {
                OwnIDCheckmarkView()
            }
        }
        .frame(width: 180, height: 60)
    }

    private func identifiedCreatePasskeyWidget(
        identity: String,
        viewModel: OwnIDCreatePasskeyWidgetViewModel?,
        loginID: String,
        instanceName: InstanceName,
        buttonProbe: WidgetButtonProbe,
        onNewPasskey: @escaping @MainActor (BoostFlowCreatePasskeyResponse) -> Void,
        onReset: @escaping @MainActor () -> Void
    ) -> some View {
        createPasskeyWidget(
            viewModel: viewModel,
            loginID: loginID,
            instanceName: instanceName,
            buttonProbe: buttonProbe,
            onNewPasskey: onNewPasskey,
            onReset: onReset
        )
        .id(identity)
    }

    private func startMountedFlow<Content: View>(
        _ host: SwiftUIRuntimeHost<Content>,
        buttonProbe: WidgetButtonProbe
    ) async throws {
        await host.settle(cycles: 1)
        let action = try #require(buttonProbe.latestAction, "Expected mounted widget action")
        action()
    }

    private func initializeDefaultWidgetInstance(
        instanceName: InstanceName,
        loginFlow: (any BoostLoginFlow)? = nil,
        createPasskeyFlow: (any BoostCreatePasskeyFlow)? = nil
    ) throws {
        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = "WidgetRuntime\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        }

        let container = try #require(OwnID.getInstanceContainer(instanceName))
        if let loginFlow {
            container.register((any BoostLoginFlow).self, instance: loginFlow)
        }
        if let createPasskeyFlow {
            container.register((any BoostCreatePasskeyFlow).self, instance: createPasskeyFlow)
        }
    }

    private func uniqueWidgetInstanceName(_ prefix: String) -> InstanceName {
        InstanceName(value: "OwnIDWidgetRuntimeUpdateTests-\(prefix)-\(UUID().uuidString)")
    }
}

@MainActor
private final class WidgetButtonProbe {
    private(set) var latestAction: (() -> Void)?
    private(set) var latestState: ButtonSlotSnapshot?

    func record(isBusy: Bool, isEnabled: Bool, action: @escaping () -> Void, accessibilityLabel: String) {
        latestState = ButtonSlotSnapshot(isBusy: isBusy, isEnabled: isEnabled, accessibilityLabel: accessibilityLabel)
        latestAction = action
    }
}

private struct RecordingWidgetButton: View {
    private let isBusy: Bool
    private let isEnabled: Bool
    private let action: () -> Void
    private let accessibilityLabel: String

    init(
        isBusy: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String,
        probe: WidgetButtonProbe
    ) {
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        probe.record(isBusy: isBusy, isEnabled: isEnabled, action: action, accessibilityLabel: accessibilityLabel)
    }

    var body: some View {
        Button(action: action) {
            Text(isBusy ? "Busy" : "Ready")
        }
        .disabled(!isEnabled)
        .accessibilityLabelCompat(Text(accessibilityLabel))
    }
}

@MainActor
private final class WidgetCheckmarkProbe {
    private(set) var didRender = false

    func recordRender() {
        didRender = true
    }
}

private struct RecordingWidgetCheckmark: View {
    init(probe: WidgetCheckmarkProbe) {
        probe.recordRender()
    }

    var body: some View {
        Color.clear
            .frame(width: 8, height: 8)
    }
}

@MainActor
private final class WidgetCallbackProbe<Value: Sendable> {
    private var values: [Value] = []
    private var waiters: [CheckedContinuation<Value, Never>] = []

    var isEmpty: Bool {
        values.isEmpty
    }

    func record(_ value: Value) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: value)
        } else {
            values.append(value)
        }
    }

    func next() async -> Value {
        if !values.isEmpty {
            return values.removeFirst()
        }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
