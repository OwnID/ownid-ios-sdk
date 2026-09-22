import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-060, UI-PRESENT-370
@MainActor
@Suite(.serialized)
struct SDKPresentedOperationContentEnvironmentRuntimeTests {

    @Test
    func `Operation UI container propagates synchronous presenter errors`() throws {
        let operationContainer = BottomSheetOperationUIContainerImpl(
            instanceResolver: DIContainerImpl(scopeName: "startup-error"),
            presenter: ThrowingBottomSheetPresenter(error: BottomSheetPresentationError.hostNotReady),
            themeStore: OwnIDThemeStore(),
            languageTagsProvider: nil,
            logger: nil
        )

        do {
            try operationContainer.show(controller: ActiveLoginIDCollectOperationController())
            Issue.record("Expected presenter startup error")
        } catch let error as BottomSheetPresentationError {
            #expect(error.rawValue == BottomSheetPresentationError.hostNotReady.rawValue)
        } catch {
            Issue.record("Unexpected presenter error: \(error)")
        }
    }

    @Test
    func `Operation UI container maps delayed presentation failure to one exact system abort`() throws {
        let presenter = CapturingBottomSheetPresenter()
        let controller = ActiveLoginIDCollectOperationController()
        let operationContainer = BottomSheetOperationUIContainerImpl(
            instanceResolver: DIContainerImpl(scopeName: "delayed-presentation-error"),
            presenter: presenter,
            themeStore: OwnIDThemeStore(),
            languageTagsProvider: nil,
            logger: nil
        )

        try operationContainer.show(controller: controller)
        presenter.fail(.presentationAcknowledgementTimedOut)

        #expect(controller.abortReasons.count == 1)
        let abortReason = try #require(controller.abortReasons.first)
        guard case .systemError(let details) = abortReason else {
            Issue.record("Expected a system-error abort, got \(abortReason)")
            return
        }
        #expect(details == BottomSheetPresentationError.presentationAcknowledgementTimedOut.localizedDescription)
    }

    @Test
    func `Operation settlement starts dismissal before SwiftUI appearance`() async throws {
        let presenter = CapturingBottomSheetPresenter()
        let controller = ImmediatelySettledLoginIDCollectOperationController()
        let operationContainer = BottomSheetOperationUIContainerImpl(
            instanceResolver: DIContainerImpl(scopeName: "settled-before-appearance"),
            presenter: presenter,
            themeStore: OwnIDThemeStore(),
            languageTagsProvider: nil,
            logger: nil
        )

        try operationContainer.show(controller: controller)
        for _ in 0..<100 where presenter.containerController?.isClosing != true {
            await Task.yield()
        }

        #expect(presenter.containerController?.isClosing == true)
        #expect(controller.abortReasons.isEmpty)
    }

    @Test
    func `Theme bridge publishes captured SDK theme without changing app hosted environment`() async throws {
        let instanceName = InstanceName(value: "theme-bridge-\(UUID().uuidString)")
        defer { OwnID.destroy(instanceName: instanceName) }

        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = "ThemeBridge\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        }

        let expectedTheme = OwnIDTheme.capture(colorScheme: .dark, primary: .green, onPrimary: .black)
        let recorder = RuntimeSnapshotRecorder<OwnIDTheme?>()
        let container = try #require(OwnID.getInstanceContainer(instanceName))
        let themeStore = try #require(container.getOrNil(type: OwnIDThemeStore.self))
        let host = SwiftUIRuntimeHost(
            rootView: ThemeBridgeFixture(instanceName: instanceName, recorder: recorder)
                .environment(\.colorScheme, .dark)
        )
        defer { host.close() }

        try await waitForTheme(expectedTheme, in: themeStore, host: host)

        #expect(themeStore.theme == expectedTheme)
        #expect(recorder.snapshots().contains(where: { $0 == nil }))
    }

    @Test
    func `SDK presented operation content receives SDK theme and layout direction`() async throws {
        let expectedTheme = OwnIDTheme.capture(colorScheme: .dark, primary: .green, onPrimary: .black)
        let themeStore = OwnIDThemeStore()
        themeStore.set(expectedTheme)

        let recorder = RuntimeSnapshotRecorder<OperationContentEnvironmentSnapshot>()
        let presenter = CapturingBottomSheetPresenter()
        let container = DIContainerImpl(scopeName: "sdk-presented-operation-content-environment")
        container.register(
            (any LoginIDCollectUIProvider).self,
            instance: EnvironmentCapturingLoginIDCollectUIProvider(recorder: recorder) as any LoginIDCollectUIProvider
        )
        container.register(
            (any LoginIDCollectStringsProvider).self,
            instance: StaticLoginIDCollectStringsProvider() as any LoginIDCollectStringsProvider
        )

        let operationContainer = BottomSheetOperationUIContainerImpl(
            instanceResolver: container,
            presenter: presenter,
            themeStore: themeStore,
            languageTagsProvider: StaticSDKLanguageTagsProvider(tags: [LanguageTag(language: "ar", country: "")]),
            logger: nil
        )

        try operationContainer.show(controller: ActiveLoginIDCollectOperationController())

        let viewController = try #require(presenter.viewController)
        let host = UIKitViewControllerRuntimeHost(viewController: viewController)
        defer { host.close() }

        let snapshot = try await recorder.waitForSnapshot(
            matching: { snapshot in
                snapshot.theme == expectedTheme
                    && snapshot.layoutDirection == .rightToLeft
                    && snapshot.loginIDValue == "user@example.test"
                    && snapshot.stringsTitle == "Collect login ID"
            },
            host: host,
            description: "operation content environment snapshot"
        )

        #expect(snapshot.theme == expectedTheme)
        #expect(snapshot.layoutDirection == .rightToLeft)
        #expect(snapshot.loginIDValue == "user@example.test")
        #expect(snapshot.stringsTitle == "Collect login ID")
    }
}

@MainActor
private func waitForTheme<Content: View>(
    _ expectedTheme: OwnIDTheme,
    in themeStore: OwnIDThemeStore,
    host: SwiftUIRuntimeHost<Content>
) async throws {
    for _ in 0..<50 {
        await host.settle(cycles: 1)
        if themeStore.theme == expectedTheme {
            return
        }
    }

    throw ThemeStoreTimeoutError.timedOut(observed: themeStore.theme)
}

private enum ThemeStoreTimeoutError: Error, CustomStringConvertible {
    case timedOut(observed: OwnIDTheme?)

    var description: String {
        switch self {
        case .timedOut(let observed):
            return "Timed out waiting for theme store update. Observed: \(String(describing: observed))"
        }
    }
}

private struct ThemeBridgeFixture: View {
    let instanceName: InstanceName
    let recorder: RuntimeSnapshotRecorder<OwnIDTheme?>

    var body: some View {
        ThemeEnvironmentProbe(recorder: recorder)
            .ownIDTheme(instanceName: instanceName) { _, theme in
                theme.colors.primary = .green
                theme.colors.onPrimary = .black
            }
    }
}

private struct ThemeEnvironmentProbe: View {
    @Environment(\.ownIDTheme) private var theme

    let recorder: RuntimeSnapshotRecorder<OwnIDTheme?>

    var body: some View {
        RuntimeSnapshotProbe(snapshot: theme, recorder: recorder)
            .frame(width: 1, height: 1)
    }
}

@MainActor
private final class CapturingBottomSheetPresenter: BottomSheetPresenter, @unchecked Sendable {
    private(set) var viewController: BottomSheetViewController?
    private(set) var containerController: OwnIDUIContainerController?
    private var window: UIKitRuntimeTestWindow?
    private var onFailure: (@MainActor (BottomSheetPresentationError) -> Void)?

    func show<Content: View>(
        themeStore: OwnIDThemeStore,
        onFailure: @escaping @MainActor (BottomSheetPresentationError) -> Void,
        content: @MainActor (OwnIDUIContainerController) -> Content
    ) throws {
        self.onFailure = onFailure
        let containerController = OwnIDUIContainerController(closeAction: {})
        self.containerController = containerController
        let window = UIKitRuntimeTestWindow()
        self.window = window
        viewController = BottomSheetViewController(
            expectedWindow: window,
            containerController: containerController,
            themeStore: themeStore,
            content: AnyView(content(containerController))
        )
    }

    func fail(_ error: BottomSheetPresentationError) {
        onFailure?(error)
    }
}

private final class ImmediatelySettledLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID = OperationID(type: .loginIDCollect, id: "settled-before-appearance")
    private(set) var abortReasons: [Reason] = []

    func abort(reason: Reason) {
        abortReasons.append(reason)
    }

    func whenSettled() async -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        .success(LoginID(id: "settled@example.test", type: .email))
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        AsyncStream { _ in }
    }
}

@MainActor
private final class ThrowingBottomSheetPresenter: BottomSheetPresenter, @unchecked Sendable {
    private let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func show<Content: View>(
        themeStore: OwnIDThemeStore,
        onFailure: @escaping @MainActor (BottomSheetPresentationError) -> Void,
        content: @MainActor (OwnIDUIContainerController) -> Content
    ) throws {
        throw error
    }
}

private final class ActiveLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID = OperationID(type: .loginIDCollect, id: "sdk-presented-environment")
    private let settlement = CancellablePendingValue(
        OperationResult<LoginID, LoginIDCollectOperationFailure>.canceled(.timeout)
    )

    private(set) var abortReasons: [Reason] = []

    func abort(reason: Reason) {
        abortReasons.append(reason)
    }

    func whenSettled() async -> OperationResult<LoginID, LoginIDCollectOperationFailure> {
        await settlement.wait()
    }

    @MainActor
    func stateStream() -> AsyncStream<LoginIDCollectOperationState> {
        AsyncStream { continuation in
            continuation.yield(
                .active(
                    uiState: LoginIDCollectUIState(
                        loginIDValue: "user@example.test",
                        collectableLoginIDTypes: [.email],
                        onLoginIDChange: { _ in },
                        onContinue: {},
                        onCancel: {}
                    )
                )
            )
        }
    }
}

private struct StaticLoginIDCollectStringsProvider: LoginIDCollectStringsProvider {
    func getStrings(params: LoginIDCollectStringsParams) -> AsyncStream<LoginIDCollectStrings?> {
        AsyncStream { continuation in
            continuation.yield(
                LoginIDCollectStrings(
                    title: "Collect login ID",
                    message: "Message",
                    placeholder: "Email",
                    cancel: "Cancel",
                    cta: "Continue",
                    error: "Error"
                )
            )
        }
    }
}

private struct StaticSDKLanguageTagsProvider: LanguageTagsProvider {
    let tags: [LanguageTag]

    func setLanguageTags(_ tags: [String]) {}

    var languageTags: AsyncStream<[LanguageTag]> {
        AsyncStream { continuation in
            continuation.yield(tags)
        }
    }
}

private struct EnvironmentCapturingLoginIDCollectUIProvider: LoginIDCollectUIProvider, @unchecked Sendable {
    let recorder: RuntimeSnapshotRecorder<OperationContentEnvironmentSnapshot>

    @MainActor
    func content(
        uiState: LoginIDCollectUIState,
        uiStrings: LoginIDCollectStrings,
        errorTextProvider: ((ErrorCode) -> String)?,
        isReadyForInitialFocus: Bool
    ) -> AnyView {
        AnyView(
            OperationContentEnvironmentProbe(
                recorder: recorder,
                loginIDValue: uiState.loginIDValue,
                stringsTitle: uiStrings.title
            )
        )
    }
}

private struct OperationContentEnvironmentProbe: View {
    @Environment(\.ownIDTheme) private var theme
    @Environment(\.layoutDirection) private var layoutDirection

    let recorder: RuntimeSnapshotRecorder<OperationContentEnvironmentSnapshot>
    let loginIDValue: String
    let stringsTitle: String

    var body: some View {
        RuntimeSnapshotProbe(
            snapshot: OperationContentEnvironmentSnapshot(
                theme: theme,
                layoutDirection: layoutDirection,
                loginIDValue: loginIDValue,
                stringsTitle: stringsTitle
            ),
            recorder: recorder
        )
        .frame(width: 1, height: 1)
    }
}

private struct OperationContentEnvironmentSnapshot: Equatable, Sendable {
    let theme: OwnIDTheme?
    let layoutDirection: LayoutDirection
    let loginIDValue: String
    let stringsTitle: String
}
