import Foundation
import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-110, UI-PRESENT-380, UI-PRESENT-390, UI-PRESENT-410
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
    func `Default login widget replaces owned runtime when instance changes`() async throws {
        let firstInstance = uniqueWidgetInstanceName("default-login-instance-a")
        let secondInstance = uniqueWidgetInstanceName("default-login-instance-b")
        let firstController = DeferredLoginController()
        let secondController = DeferredLoginController()
        let firstFlow = RecordingBoostLoginFlow(controllers: [firstController])
        let secondWindowProbe = WidgetWindowIDProbe()
        try initializeDefaultWidgetInstance(instanceName: firstInstance, loginFlow: firstFlow)
        try initializeDefaultWidgetInstance(instanceName: secondInstance)
        defer {
            OwnID.destroy(instanceName: firstInstance)
            OwnID.destroy(instanceName: secondInstance)
        }

        let secondContainer = try #require(OwnID.getInstanceContainer(secondInstance))
        secondContainer.registerFactory(
            (any BoostLoginFlow).self,
            dependencies: [(any UIContextProvider).self]
        ) { resolver in
            DIContextLoginFlow(
                uiContextProvider: try resolver.getOrThrow(type: (any UIContextProvider).self),
                windowProbe: secondWindowProbe,
                controller: secondController
            )
        }

        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()
        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: nil,
                loginID: "first@example.test",
                instanceName: firstInstance,
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record("old:\(response.loginID.id)") }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(firstFlow.startCount == 1)

        host.update(
            rootView: loginWidget(
                viewModel: nil,
                loginID: "second@example.test",
                instanceName: secondInstance,
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record("new:\(response.loginID.id)") }
            )
        )
        await host.settle(cycles: 3)

        #expect(
            firstController.abortReasonDescriptions
                == [Reason.userClose(details: "Login widget deinitialized").description]
        )
        #expect(buttonProbe.latestState == .ready(accessibilityLabel: widgetButtonTitle))

        await firstController.settle(.success(makeLoginResponse(id: "late@example.test")))
        await host.settle(cycles: 2)
        #expect(callbackProbe.isEmpty)

        let currentAction = try #require(buttonProbe.latestAction, "Expected replacement login widget action")
        currentAction()
        let expectedWindow = try #require(host.host.view.window)
        let resolvedWindowID = try await withSwiftUITestTimeout("replacement login UI context", seconds: 2) {
            await secondWindowProbe.next()
        }
        #expect(resolvedWindowID == ObjectIdentifier(expectedWindow))

        await secondController.settle(.success(makeLoginResponse(id: "second@example.test")))
        #expect(await callbackProbe.next() == "new:second@example.test")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Removing and readding default login widget replaces its owned model`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-login-removal")
        let firstController = DeferredLoginController()
        let secondController = DeferredLoginController()
        let flow = RecordingBoostLoginFlow(controllers: [firstController, secondController])
        try initializeDefaultWidgetInstance(instanceName: instanceName, loginFlow: flow)
        defer { OwnID.destroy(instanceName: instanceName) }

        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()
        let host = SwiftUIRuntimeHost(
            rootView: removableLoginWidget(
                isVisible: true,
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record(response.loginID.id) }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(flow.startCount == 1)

        host.update(
            rootView: removableLoginWidget(
                isVisible: false,
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record(response.loginID.id) }
            )
        )
        buttonProbe.clear()
        await host.settle(cycles: 3)
        #expect(
            firstController.abortReasonDescriptions
                == [Reason.userClose(details: "Login widget deinitialized").description]
        )

        await firstController.settle(.success(makeLoginResponse(id: "late@example.test")))
        await host.settle(cycles: 2)
        #expect(callbackProbe.isEmpty)

        host.update(
            rootView: removableLoginWidget(
                isVisible: true,
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record(response.loginID.id) }
            )
        )
        await host.settle(cycles: 3)
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(flow.startCount == 2)

        await secondController.settle(.success(makeLoginResponse(id: "new@example.test")))
        #expect(await callbackProbe.next() == "new@example.test")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Default login widget resolves its scoped UI context from the DI flow factory`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-login-ui-context")
        let controller = DeferredLoginController()
        let windowProbe = WidgetWindowIDProbe()
        try initializeDefaultWidgetInstance(instanceName: instanceName)
        defer { OwnID.destroy(instanceName: instanceName) }

        let container = try #require(OwnID.getInstanceContainer(instanceName))
        container.registerFactory(
            (any BoostLoginFlow).self,
            dependencies: [(any UIContextProvider).self]
        ) { resolver in
            let provider = try resolver.getOrThrow(type: (any UIContextProvider).self)
            return DIContextLoginFlow(
                uiContextProvider: provider,
                windowProbe: windowProbe,
                controller: controller
            )
        }

        let buttonProbe = WidgetButtonProbe()
        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: nil,
                loginID: "user@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: { _ in }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)
        let expectedWindow = try #require(host.host.view.window)
        let resolvedWindowID = try await withSwiftUITestTimeout("default login UI context", seconds: 2) {
            await windowProbe.next()
        }
        #expect(resolvedWindowID == ObjectIdentifier(expectedWindow))
        await controller.settle(.canceled(.timeout))
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
    func `Default create-passkey widget resolves its scoped UI context from the DI flow factory`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-create-passkey-ui-context")
        let controller = DeferredCreatePasskeyController()
        let windowProbe = WidgetWindowIDProbe()
        try initializeDefaultWidgetInstance(instanceName: instanceName)
        defer { OwnID.destroy(instanceName: instanceName) }

        let container = try #require(OwnID.getInstanceContainer(instanceName))
        container.registerFactory(
            (any BoostCreatePasskeyFlow).self,
            dependencies: [(any UIContextProvider).self]
        ) { resolver in
            let provider = try resolver.getOrThrow(type: (any UIContextProvider).self)
            return DIContextCreatePasskeyFlow(
                uiContextProvider: provider,
                windowProbe: windowProbe,
                controller: controller
            )
        }

        let buttonProbe = WidgetButtonProbe()
        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: "new@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { _ in },
                onReset: {}
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)
        let expectedWindow = try #require(host.host.view.window)
        let resolvedWindowID = try await withSwiftUITestTimeout("default create-passkey UI context", seconds: 2) {
            await windowProbe.next()
        }
        #expect(resolvedWindowID == ObjectIdentifier(expectedWindow))
        await controller.settle(.canceled(.timeout))
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Default create-passkey widget re-emits remembered completion with latest callback`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-create-passkey-remembered")
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
                    newPasskeyProbe.record("initial:\(response.loginID.id)")
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
        #expect(await newPasskeyProbe.next() == "initial:new@example.test")

        host.update(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: "other@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("away:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("away")
                }
            )
        )
        await host.settle(cycles: 2)
        #expect(await resetProbe.next() == "away")

        host.update(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: " new@example.test ",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("restored:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("restored")
                }
            )
        )
        await host.settle(cycles: 2)

        #expect(await newPasskeyProbe.next() == "restored:new@example.test")
        #expect(resetProbe.isEmpty)
        #expect(flow.startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Default create-passkey widget replaces owned runtime when instance changes`() async throws {
        let firstInstance = uniqueWidgetInstanceName("default-create-passkey-instance-a")
        let secondInstance = uniqueWidgetInstanceName("default-create-passkey-instance-b")
        let firstController = DeferredCreatePasskeyController()
        let secondController = DeferredCreatePasskeyController()
        let firstFlow = RecordingBoostCreatePasskeyFlow(controllers: [firstController])
        let secondWindowProbe = WidgetWindowIDProbe()
        try initializeDefaultWidgetInstance(instanceName: firstInstance, createPasskeyFlow: firstFlow)
        try initializeDefaultWidgetInstance(instanceName: secondInstance)
        defer {
            OwnID.destroy(instanceName: firstInstance)
            OwnID.destroy(instanceName: secondInstance)
        }

        let secondContainer = try #require(OwnID.getInstanceContainer(secondInstance))
        secondContainer.registerFactory(
            (any BoostCreatePasskeyFlow).self,
            dependencies: [(any UIContextProvider).self]
        ) { resolver in
            DIContextCreatePasskeyFlow(
                uiContextProvider: try resolver.getOrThrow(type: (any UIContextProvider).self),
                windowProbe: secondWindowProbe,
                controller: secondController
            )
        }

        let buttonProbe = WidgetButtonProbe()
        let newPasskeyProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: "first@example.test",
                instanceName: firstInstance,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("old:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("old")
                }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(firstFlow.startCount == 1)

        host.update(
            rootView: createPasskeyWidget(
                viewModel: nil,
                loginID: "second@example.test",
                instanceName: secondInstance,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    newPasskeyProbe.record("new:\(response.loginID.id)")
                },
                onReset: {
                    resetProbe.record("new")
                }
            )
        )
        await host.settle(cycles: 3)

        #expect(
            firstController.abortReasonDescriptions
                == [Reason.userClose(details: "Create-passkey widget deinitialized").description]
        )
        #expect(resetProbe.isEmpty)
        #expect(buttonProbe.latestState == .ready(accessibilityLabel: widgetButtonTitle))

        await firstController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "late@example.test"))))
        await host.settle(cycles: 2)
        #expect(newPasskeyProbe.isEmpty)
        #expect(resetProbe.isEmpty)

        let currentAction = try #require(buttonProbe.latestAction, "Expected replacement create-passkey widget action")
        currentAction()
        let expectedWindow = try #require(host.host.view.window)
        let resolvedWindowID = try await withSwiftUITestTimeout("replacement create-passkey UI context", seconds: 2) {
            await secondWindowProbe.next()
        }
        #expect(resolvedWindowID == ObjectIdentifier(expectedWindow))

        await secondController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "second@example.test"))))
        #expect(await newPasskeyProbe.next() == "new:second@example.test")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Removing and readding default create-passkey widget replaces its owned model`() async throws {
        let instanceName = uniqueWidgetInstanceName("default-create-passkey-removal")
        let firstController = DeferredCreatePasskeyController()
        let secondController = DeferredCreatePasskeyController()
        let flow = RecordingBoostCreatePasskeyFlow(controllers: [firstController, secondController])
        try initializeDefaultWidgetInstance(instanceName: instanceName, createPasskeyFlow: flow)
        defer { OwnID.destroy(instanceName: instanceName) }

        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()
        let host = SwiftUIRuntimeHost(
            rootView: removableCreatePasskeyWidget(
                isVisible: true,
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in callbackProbe.record(response.loginID.id) },
                onReset: { resetProbe.record("reset") }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(flow.startCount == 1)

        host.update(
            rootView: removableCreatePasskeyWidget(
                isVisible: false,
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in callbackProbe.record(response.loginID.id) },
                onReset: { resetProbe.record("reset") }
            )
        )
        buttonProbe.clear()
        await host.settle(cycles: 3)
        #expect(
            firstController.abortReasonDescriptions
                == [Reason.userClose(details: "Create-passkey widget deinitialized").description]
        )

        await firstController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "late@example.test"))))
        await host.settle(cycles: 2)
        #expect(callbackProbe.isEmpty)
        #expect(resetProbe.isEmpty)

        host.update(
            rootView: removableCreatePasskeyWidget(
                isVisible: true,
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in callbackProbe.record(response.loginID.id) },
                onReset: { resetProbe.record("reset") }
            )
        )
        await host.settle(cycles: 3)
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        #expect(flow.startCount == 2)

        await secondController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await callbackProbe.next() == "new@example.test")
        #expect(resetProbe.isEmpty)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Supplied login view model survives instance change and uses latest success callback`() async throws {
        let firstInstance = uniqueWidgetInstanceName("supplied-login-instance-a")
        let secondInstance = uniqueWidgetInstanceName("supplied-login-instance-b")
        let controller = DeferredLoginController()
        var startCount = 0
        let viewModel = makeLoginViewModel { _, _ in
            startCount += 1
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: " first@example.test ",
                instanceName: firstInstance,
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
                instanceName: secondInstance,
                buttonProbe: buttonProbe,
                onLogin: { response in
                    callbackProbe.record("updated:\(response.loginID.id)")
                }
            )
        )
        await host.settle(cycles: 2)

        #expect(buttonProbe.latestState == .busy(accessibilityLabel: widgetButtonTitle))

        await controller.settle(.success(makeLoginResponse(id: "second@example.test")))
        let callback = await callbackProbe.next()

        #expect(callback == "updated:second@example.test")
        #expect(startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Replacing supplied login view model switches state effects and current window`() async throws {
        let oldController = DeferredLoginController()
        let newController = DeferredLoginController()
        let oldViewModel = makeLoginViewModel { _, _ in oldController }
        var newWindow: UIWindow?
        let newViewModel = makeLoginViewModel { window, _ in
            newWindow = window
            return newController
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: oldViewModel,
                loginID: "old@example.test",
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record("old:\(response.loginID.id)") }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        await host.settle(cycles: 1)
        let initialWindow = try #require(host.host.view.window)
        oldViewModel.startFlow(window: initialWindow, loginID: "old@example.test")
        await host.settle(cycles: 2)
        #expect(buttonProbe.latestState == .busy(accessibilityLabel: widgetButtonTitle))

        host.update(
            rootView: loginWidget(
                viewModel: newViewModel,
                loginID: "new@example.test",
                buttonProbe: buttonProbe,
                onLogin: { response in callbackProbe.record("new:\(response.loginID.id)") }
            )
        )
        await host.settle(cycles: 2)
        #expect(buttonProbe.latestState == .ready(accessibilityLabel: widgetButtonTitle))

        await oldController.settle(.success(makeLoginResponse(id: "late@example.test")))
        await host.settle(cycles: 2)
        #expect(callbackProbe.isEmpty)

        let currentAction = try #require(buttonProbe.latestAction, "Expected replacement login action")
        currentAction()
        await host.settle(cycles: 2)
        #expect(buttonProbe.latestState == .busy(accessibilityLabel: widgetButtonTitle))
        #expect(newWindow === host.host.view.window)
        await newController.settle(.success(makeLoginResponse(id: "new@example.test")))
        #expect(await callbackProbe.next() == "new:new@example.test")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Mounted login widget forwards its hosting window to the view model`() async throws {
        let controller = DeferredLoginController()
        var receivedWindow: UIWindow?
        let viewModel = makeLoginViewModel { window, _ in
            receivedWindow = window
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let host = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: buttonProbe,
                onLogin: { _ in }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)

        #expect(receivedWindow === host.host.view.window)
        await controller.settle(.canceled(.timeout))
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Mounted create-passkey widget forwards its hosting window to the view model`() async throws {
        let controller = DeferredCreatePasskeyController()
        var receivedWindow: UIWindow?
        let viewModel = makeCreatePasskeyViewModel { window, _ in
            receivedWindow = window
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { _ in },
                onReset: {}
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }

        try await startMountedFlow(host, buttonProbe: buttonProbe)

        #expect(receivedWindow === host.host.view.window)
        await controller.settle(.canceled(.timeout))
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Detached login widget action cannot start and rehosted action uses the new window`() async throws {
        let firstController = DeferredLoginController()
        let secondController = DeferredLoginController()
        var receivedWindows: [UIWindow] = []
        var startCount = 0
        let viewModel = makeLoginViewModel { window, _ in
            startCount += 1
            receivedWindows.append(window)
            return startCount == 1 ? firstController : secondController
        }

        let firstButtonProbe = WidgetButtonProbe()
        let firstHost = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: firstButtonProbe,
                onLogin: { _ in }
            ),
            size: CGSize(width: 240, height: 120)
        )
        try await startMountedFlow(firstHost, buttonProbe: firstButtonProbe)
        await firstController.settle(.canceled(.timeout))
        await firstHost.settle(cycles: 3)
        #expect(viewModel.uiState == .init(isRunning: false))
        let detachedAction = try #require(firstButtonProbe.latestAction)
        firstHost.close()
        await Task.yield()

        detachedAction()
        #expect(startCount == 1)
        #expect(viewModel.uiState == .init(isRunning: false))

        let secondButtonProbe = WidgetButtonProbe()
        let secondHost = SwiftUIRuntimeHost(
            rootView: loginWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: secondButtonProbe,
                onLogin: { _ in }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { secondHost.close() }
        try await startMountedFlow(secondHost, buttonProbe: secondButtonProbe)

        let expectedWindow = try #require(secondHost.host.view.window)
        #expect(startCount == 2)
        #expect(receivedWindows.last === expectedWindow)
        await secondController.settle(.canceled(.timeout))
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Detached create-passkey widget action cannot start and rehosted action uses the new window`() async throws {
        let firstController = DeferredCreatePasskeyController()
        let secondController = DeferredCreatePasskeyController()
        var receivedWindows: [UIWindow] = []
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { window, _ in
            startCount += 1
            receivedWindows.append(window)
            return startCount == 1 ? firstController : secondController
        }

        let firstButtonProbe = WidgetButtonProbe()
        let firstHost = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: firstButtonProbe,
                onNewPasskey: { _ in },
                onReset: {}
            ),
            size: CGSize(width: 240, height: 120)
        )
        try await startMountedFlow(firstHost, buttonProbe: firstButtonProbe)
        await firstController.settle(.canceled(.timeout))
        await firstHost.settle(cycles: 3)
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))
        let detachedAction = try #require(firstButtonProbe.latestAction)
        firstHost.close()
        await Task.yield()

        detachedAction()
        #expect(startCount == 1)
        #expect(viewModel.uiState == .init(isRunning: false, showCheckmark: false))

        let secondButtonProbe = WidgetButtonProbe()
        let secondHost = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "user@example.test",
                buttonProbe: secondButtonProbe,
                onNewPasskey: { _ in },
                onReset: {}
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { secondHost.close() }
        try await startMountedFlow(secondHost, buttonProbe: secondButtonProbe)

        let expectedWindow = try #require(secondHost.host.view.window)
        #expect(startCount == 2)
        #expect(receivedWindows.last === expectedWindow)
        await secondController.settle(.canceled(.timeout))
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Login widget callback-only update keeps active flow and uses latest success callback`() async throws {
        let controller = DeferredLoginController()
        var startCount = 0
        let viewModel = makeLoginViewModel { _, _ in
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
        let viewModel = makeLoginViewModel { _, _ in
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
    func `Supplied create-passkey view model survives instance change and uses latest callback`() async throws {
        let firstInstance = uniqueWidgetInstanceName("supplied-create-passkey-instance-a")
        let secondInstance = uniqueWidgetInstanceName("supplied-create-passkey-instance-b")
        let controller = DeferredCreatePasskeyController()
        var startCount = 0
        let viewModel = makeCreatePasskeyViewModel { _, _ in
            startCount += 1
            return controller
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: " first@example.test ",
                instanceName: firstInstance,
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
                instanceName: secondInstance,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in
                    callbackProbe.record("updated:\(response.loginID.id)")
                }
            )
        )
        await host.settle(cycles: 2)

        #expect(buttonProbe.latestState == .busy(accessibilityLabel: widgetButtonTitle))

        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "second@example.test"))))
        let callback = await callbackProbe.next()

        #expect(callback == "updated:second@example.test")
        #expect(startCount == 1)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Replacing supplied create-passkey view model switches state effects and current window`() async throws {
        let oldController = DeferredCreatePasskeyController()
        let newController = DeferredCreatePasskeyController()
        let oldViewModel = makeCreatePasskeyViewModel { _, _ in oldController }
        var newWindow: UIWindow?
        let newViewModel = makeCreatePasskeyViewModel { window, _ in
            newWindow = window
            return newController
        }
        let buttonProbe = WidgetButtonProbe()
        let callbackProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: oldViewModel,
                loginID: "old@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in callbackProbe.record("old:\(response.loginID.id)") },
                onReset: { resetProbe.record("old") }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        await host.settle(cycles: 1)
        let initialWindow = try #require(host.host.view.window)
        oldViewModel.startFlow(window: initialWindow, loginID: "old@example.test")
        await host.settle(cycles: 2)
        #expect(buttonProbe.latestState == .busy(accessibilityLabel: widgetButtonTitle))

        host.update(
            rootView: createPasskeyWidget(
                viewModel: newViewModel,
                loginID: "new@example.test",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in callbackProbe.record("new:\(response.loginID.id)") },
                onReset: { resetProbe.record("new") }
            )
        )
        await host.settle(cycles: 2)
        #expect(buttonProbe.latestState == .ready(accessibilityLabel: widgetButtonTitle))

        await oldController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "late@example.test"))))
        await host.settle(cycles: 2)
        #expect(callbackProbe.isEmpty)
        #expect(resetProbe.isEmpty)

        let currentAction = try #require(buttonProbe.latestAction, "Expected replacement create-passkey action")
        currentAction()
        await host.settle(cycles: 2)
        #expect(buttonProbe.latestState == .busy(accessibilityLabel: widgetButtonTitle))
        #expect(newWindow === host.host.view.window)
        await newController.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "new@example.test"))))
        #expect(await callbackProbe.next() == "new:new@example.test")
        #expect(resetProbe.isEmpty)
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Create passkey widget exposes completion checkmark after successful create-passkey result`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _, _ in controller }
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
        let viewModel = makeCreatePasskeyViewModel { _, _ in controller }
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
    func `Create passkey widget treats absent and literal nil login IDs as distinct updates`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _, _ in controller }
        let buttonProbe = WidgetButtonProbe()
        let newPasskeyProbe = WidgetCallbackProbe<String>()
        let resetProbe = WidgetCallbackProbe<String>()

        let host = SwiftUIRuntimeHost(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: nil,
                buttonProbe: buttonProbe,
                onNewPasskey: { response in newPasskeyProbe.record(response.loginID.id) },
                onReset: { resetProbe.record("reset") }
            ),
            size: CGSize(width: 240, height: 120)
        )
        defer { host.close() }
        try await startMountedFlow(host, buttonProbe: buttonProbe)
        await controller.settle(.success(.createPasskey(makeCreatePasskeyResponse(id: "created@example.test"))))
        #expect(await newPasskeyProbe.next() == "created@example.test")
        #expect(resetProbe.isEmpty)

        host.update(
            rootView: createPasskeyWidget(
                viewModel: viewModel,
                loginID: "nil",
                buttonProbe: buttonProbe,
                onNewPasskey: { response in newPasskeyProbe.record(response.loginID.id) },
                onReset: { resetProbe.record("reset") }
            )
        )
        await host.settle(cycles: 1)

        #expect(await resetProbe.next() == "reset")
    }

    @available(iOS 16.0, *)
    @Test(.timeLimit(.minutes(1)))
    func `Create passkey widget callback-only update keeps completion and updates later reset callback`() async throws {
        let controller = DeferredCreatePasskeyController()
        let viewModel = makeCreatePasskeyViewModel { _, _ in controller }
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
        .iconButton { isBusy, isEnabled, action, accessibilityLabel, _ in
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
        loginID: String?,
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
        .iconButton { isBusy, isEnabled, action, accessibilityLabel, _ in
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

    @ViewBuilder
    private func removableLoginWidget(
        isVisible: Bool,
        instanceName: InstanceName,
        buttonProbe: WidgetButtonProbe,
        onLogin: @escaping @MainActor (BoostFlowLoginResponse) -> Void
    ) -> some View {
        if isVisible {
            loginWidget(
                viewModel: nil,
                loginID: "user@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onLogin: onLogin
            )
        }
    }

    @ViewBuilder
    private func removableCreatePasskeyWidget(
        isVisible: Bool,
        instanceName: InstanceName,
        buttonProbe: WidgetButtonProbe,
        onNewPasskey: @escaping @MainActor (BoostFlowCreatePasskeyResponse) -> Void,
        onReset: @escaping @MainActor () -> Void
    ) -> some View {
        if isVisible {
            createPasskeyWidget(
                viewModel: nil,
                loginID: "user@example.test",
                instanceName: instanceName,
                buttonProbe: buttonProbe,
                onNewPasskey: onNewPasskey,
                onReset: onReset
            )
        }
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

    func clear() {
        latestAction = nil
        latestState = nil
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
