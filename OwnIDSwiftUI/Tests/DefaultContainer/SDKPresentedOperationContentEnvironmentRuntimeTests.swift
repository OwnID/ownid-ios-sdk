import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@MainActor
@Suite(.serialized)
struct SDKPresentedOperationContentEnvironmentRuntimeTests {

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

        operationContainer.show(controller: ActiveLoginIDCollectOperationController())

        let viewController = try #require(presenter.viewController)
        let host = ViewControllerRuntimeHost(viewController: viewController)
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

    func show<Content: View>(
        themeStore: OwnIDThemeStore,
        onFailure: @escaping @MainActor (Reason) -> Void,
        content: @escaping @MainActor (OwnIDUIContainerController) -> Content
    ) {
        let containerController = OwnIDUIContainerController(closeAction: {})
        viewController = BottomSheetViewController(
            content: AnyView(content(containerController)),
            themeStore: themeStore,
            containerController: containerController
        )
    }
}

@MainActor
private final class ViewControllerRuntimeHost: SwiftUIRuntimeSettlingHost {
    private let window: RuntimeHostWindow
    private let rootViewController = UIViewController()
    private let viewController: UIViewController

    init(viewController: UIViewController, size: CGSize = CGSize(width: 320, height: 480)) {
        self.viewController = viewController
        self.window = RuntimeHostWindow(frame: CGRect(origin: .zero, size: size))

        window.rootViewController = rootViewController
        window.makeKeyAndVisible()

        rootViewController.view.frame = window.bounds
        rootViewController.addChild(viewController)
        rootViewController.view.addSubview(viewController.view)
        viewController.view.frame = rootViewController.view.bounds
        viewController.didMove(toParent: rootViewController)

        layout()
    }

    func settle(cycles: Int = 4) async {
        for _ in 0..<cycles {
            await Task.yield()
            layout()
        }
    }

    func layout() {
        rootViewController.view.setNeedsLayout()
        rootViewController.view.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
    }

    func close() {
        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
private final class RuntimeHostWindow: UIWindow {
    override var canBecomeKey: Bool { true }
}

private final class ActiveLoginIDCollectOperationController: LoginIDCollectOperationController, @unchecked Sendable {
    let operationID = OperationID(type: .loginIDCollect, id: "sdk-presented-environment")
    private let settlement = CancellablePendingValue(
        OperationResult<LoginID, LoginIDCollectOperationFailure>.canceled(.timeout)
    )

    func abort(reason: Reason) {}

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
