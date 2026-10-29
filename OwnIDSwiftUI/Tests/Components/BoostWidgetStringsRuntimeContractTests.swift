import Foundation
import LocalAuthentication
import SwiftUI
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-300, UI-PRESENT-430
@MainActor
@Suite(.serialized)
struct BoostWidgetStringsRuntimeContractTests {

    @Test
    func `Boost strings use defaults retain nil updates apply values and reset on destroy`() async throws {
        let missingInstanceName = uniqueInstanceName("missing-instance")
        let missingProviderName = uniqueInstanceName("missing-provider")
        let lifecycleName = uniqueInstanceName("destroy")
        defer {
            OwnID.destroy(instanceName: missingProviderName)
            OwnID.destroy(instanceName: lifecycleName)
        }

        let missingInstanceRecorder = RuntimeSnapshotRecorder<String>()
        let missingInstanceHost = makeHost(instanceName: missingInstanceName, recorder: missingInstanceRecorder)
        _ = try await waitForLabel(
            BoostWidgetStrings.default.skipPassword,
            recorder: missingInstanceRecorder,
            host: missingInstanceHost,
            description: "embedded strings without an instance"
        )
        missingInstanceHost.close()

        try initialize(instanceName: missingProviderName)
        let missingProviderContainer = try #require(OwnID.getInstanceContainer(missingProviderName))
        missingProviderContainer.remove((any BoostWidgetStringsProvider).self)

        let missingProviderRecorder = RuntimeSnapshotRecorder<String>()
        let missingProviderHost = makeHost(instanceName: missingProviderName, recorder: missingProviderRecorder)
        _ = try await waitForLabel(
            BoostWidgetStrings.default.skipPassword,
            recorder: missingProviderRecorder,
            host: missingProviderHost,
            description: "embedded strings without a provider"
        )
        missingProviderHost.close()

        let provider = ControlledBoostWidgetStringsProvider()
        try initialize(instanceName: lifecycleName)
        let lifecycleContainer = try #require(OwnID.getInstanceContainer(lifecycleName))
        lifecycleContainer.register((any BoostWidgetStringsProvider).self, instance: provider)

        let recorder = RuntimeSnapshotRecorder<String>()
        let host = makeHost(instanceName: lifecycleName, recorder: recorder)
        defer { host.close() }

        _ = try await waitForLabel(
            BoostWidgetStrings.default.skipPassword,
            recorder: recorder,
            host: host,
            description: "embedded strings before the first provider value"
        )
        await provider.waitForSubscription()

        let stringsA = BoostWidgetStrings(skipPassword: "Provider A", or: "or A")
        #expect(provider.yield(stringsA))
        _ = try await waitForLabel(
            stringsA.skipPassword,
            recorder: recorder,
            host: host,
            description: "first provider strings"
        )

        #expect(provider.yield(nil))
        await host.settle(cycles: 20)
        #expect(recorder.snapshots().last == stringsA.skipPassword)

        let stringsB = BoostWidgetStrings(skipPassword: "Provider B", or: "or B")
        #expect(provider.yield(stringsB))
        _ = try await waitForLabel(
            stringsB.skipPassword,
            recorder: recorder,
            host: host,
            description: "updated provider strings"
        )

        OwnID.destroy(instanceName: lifecycleName)
        _ = try await waitForLabel(
            BoostWidgetStrings.default.skipPassword,
            recorder: recorder,
            host: host,
            description: "embedded strings after destroy"
        )
        await provider.waitForTermination()

        #expect(provider.yield(BoostWidgetStrings(skipPassword: "Late old value", or: "late")) == false)
        await host.settle(cycles: 20)
        #expect(recorder.snapshots().last == BoostWidgetStrings.default.skipPassword)
    }

    @Test
    func `Same name reinitialization resets strings and rejects the old subscription`() async throws {
        let instanceName = uniqueInstanceName("reinitialize")
        defer { OwnID.destroy(instanceName: instanceName) }

        let oldProvider = ControlledBoostWidgetStringsProvider()
        try initialize(instanceName: instanceName)
        let oldContainer = try #require(OwnID.getInstanceContainer(instanceName))
        oldContainer.register((any BoostWidgetStringsProvider).self, instance: oldProvider)

        let recorder = RuntimeSnapshotRecorder<String>()
        let host = makeHost(instanceName: instanceName, recorder: recorder)
        defer { host.close() }

        await oldProvider.waitForSubscription()
        let oldStrings = BoostWidgetStrings(skipPassword: "Old instance value", or: "old")
        #expect(oldProvider.yield(oldStrings))
        _ = try await waitForLabel(
            oldStrings.skipPassword,
            recorder: recorder,
            host: host,
            description: "old instance strings"
        )

        let snapshotCountBeforeReinitialization = recorder.snapshots().count
        try initialize(instanceName: instanceName)
        _ = try await waitForLabel(
            BoostWidgetStrings.default.skipPassword,
            recorder: recorder,
            host: host,
            afterSnapshotCount: snapshotCountBeforeReinitialization,
            description: "embedded strings after same-name reinitialization"
        )
        await oldProvider.waitForTermination()

        #expect(oldProvider.yield(BoostWidgetStrings(skipPassword: "Late old value", or: "late")) == false)
        await host.settle(cycles: 20)
        #expect(
            recorder.snapshots().dropFirst(snapshotCountBeforeReinitialization).contains("Late old value") == false
        )
    }

    @Test(arguments: ["boost", "login", "create"])
    func `Device icon uses native type with explicit strings`(surface: String) async throws {
        guard #available(iOS 14, *) else { return }
        let referenceName = uniqueInstanceName("icon-reference")
        let faceHost = makeIconHost(surface: surface, instanceName: referenceName, referenceIcon: "faceid")
        let touchHost = makeIconHost(surface: surface, instanceName: referenceName, referenceIcon: "touchid")
        defer { faceHost.close(); touchHost.close() }
        await faceHost.settle()
        await touchHost.settle()
        let faceAppearance = iconAppearance(of: faceHost)
        let touchAppearance = iconAppearance(of: touchHost)
        if faceAppearance == touchAppearance {
            let directory = FileManager.default.temporaryDirectory
            let faceURL = directory.appendingPathComponent("OwnIDBiometrySimple-\(surface)-face.png")
            let touchURL = directory.appendingPathComponent("OwnIDBiometrySimple-\(surface)-touch.png")
            try? faceAppearance.write(to: faceURL)
            try? touchAppearance.write(to: touchURL)
            print("Indistinct icon reference diagnostics: \(faceURL.path), \(touchURL.path)")
        }
        if #available(iOS 14, *) { #expect(faceAppearance != touchAppearance) }

        var scenarios: [(name: String, type: LABiometryType, usable: Bool, enrolled: Bool?, lockedOut: Bool?, fido: Bool, metadataIcon: String, expectedIcon: String)] = [
            ("usable Touch ID", .touchID, true, true, false, true, "faceid", "touchid"),
            ("pre-FIDO usable Touch ID", .touchID, true, true, false, false, "faceid", "touchid"),
            ("not enrolled Touch ID", .touchID, false, false, false, true, "faceid", "touchid"),
            ("locked out Touch ID", .touchID, false, true, true, true, "faceid", "touchid"),
            ("pre-FIDO not enrolled Touch ID", .touchID, false, false, false, false, "faceid", "touchid"),
            ("usable Face ID", .faceID, true, true, false, true, "touchid", "faceid"),
            ("unusable Face ID", .faceID, false, false, false, true, "touchid", "faceid"),
            ("no biometry", .none, false, nil, nil, true, "touchid", "faceid"),
            ("unrecognized native type", try #require(LABiometryType(rawValue: 999)), true, nil, nil, true, "touchid", "faceid"),
        ]
        if #available(iOS 17, *) { scenarios.append(("Optic ID", .opticID, true, true, false, true, "touchid", "faceid")) }
        for scenario in scenarios {
            let instanceName = uniqueInstanceName("icon-matrix")
            defer { OwnID.destroy(instanceName: instanceName) }
            try initialize(instanceName: instanceName)
            let container = try #require(OwnID.getInstanceContainer(instanceName))
            container.register((any LocalInfo).self, instance: WidgetIconLocalInfo(
                isSystemFidoCapable: scenario.fido,
                biometryType: scenario.type, isBiometryUsable: scenario.usable,
                isBiometryEnrolled: scenario.enrolled, isBiometryLockedOut: scenario.lockedOut,
                biometryIconSystemName: scenario.metadataIcon
            ))
            let recorder = RuntimeSnapshotRecorder<Image>()
            let slotHost = makeIconHost(surface: surface, instanceName: instanceName, imageRecorder: recorder)
            let host = makeIconHost(surface: surface, instanceName: instanceName)
            defer { slotHost.close(); host.close() }
            _ = try await recorder.waitForSnapshot(
                matching: { $0 == Image(systemName: scenario.expectedIcon) }, host: slotHost,
                description: "\(surface): \(scenario.name) public icon value"
            )
            let expectedAppearance = scenario.expectedIcon == "touchid" ? touchAppearance : faceAppearance
            try await waitForIcon(expectedAppearance, host: host, description: "\(surface): \(scenario.name) default wiring")
        }
    }

    @Test(arguments: ["boost", "login", "create"])
    func `Device icon follows named instance lifecycle independently of explicit strings`(surface: String) async throws {
        guard #available(iOS 14, *) else { return }
        let instanceName = uniqueInstanceName("icon-lifecycle")
        defer { OwnID.destroy(instanceName: instanceName) }
        let faceHost = makeIconHost(surface: surface, instanceName: instanceName, referenceIcon: "faceid")
        let touchHost = makeIconHost(surface: surface, instanceName: instanceName, referenceIcon: "touchid")
        let recorder = RuntimeSnapshotRecorder<Image>()
        let slotHost = makeIconHost(surface: surface, instanceName: instanceName, imageRecorder: recorder)
        let host = makeIconHost(surface: surface, instanceName: instanceName)
        defer { faceHost.close(); touchHost.close(); slotHost.close(); host.close() }
        await faceHost.settle()
        await touchHost.settle()
        let faceAppearance = iconAppearance(of: faceHost)
        let touchAppearance = iconAppearance(of: touchHost)
        if faceAppearance == touchAppearance {
            let directory = FileManager.default.temporaryDirectory
            let faceURL = directory.appendingPathComponent("OwnIDBiometrySimple-\(surface)-face.png")
            let touchURL = directory.appendingPathComponent("OwnIDBiometrySimple-\(surface)-touch.png")
            try? faceAppearance.write(to: faceURL)
            try? touchAppearance.write(to: touchURL)
            print("Indistinct icon reference diagnostics: \(faceURL.path), \(touchURL.path)")
        }
        #expect(faceAppearance != touchAppearance)
        var observedImages = 0
        try await waitForIcon(faceAppearance, host: host, description: "before initialization")
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "faceid") }, afterSnapshotCount: observedImages,
            host: slotHost, description: "before initialization: public icon value"
        )
        observedImages = recorder.snapshots().count

        func initializeWithBiometry(_ type: LABiometryType, usable: Bool) throws {
            try initialize(instanceName: instanceName)
            let container = try #require(OwnID.getInstanceContainer(instanceName))
            container.register((any LocalInfo).self, instance: WidgetIconLocalInfo(
                biometryType: type, isBiometryUsable: usable, biometryIconSystemName: "faceid"
            ))
        }
        try initializeWithBiometry(.touchID, usable: true)
        try await waitForIcon(touchAppearance, host: host, description: "created instance")
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "touchid") }, afterSnapshotCount: observedImages,
            host: slotHost, description: "created instance: public icon value"
        )
        observedImages = recorder.snapshots().count
        #expect(iconAppearance(of: faceHost) == faceAppearance)
        #expect(iconAppearance(of: touchHost) == touchAppearance)
        try initializeWithBiometry(.faceID, usable: false)
        try await waitForIcon(faceAppearance, host: host, description: "reinitialized Face instance")
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "faceid") }, afterSnapshotCount: observedImages,
            host: slotHost, description: "reinitialized Face instance: public icon value"
        )
        observedImages = recorder.snapshots().count
        try initializeWithBiometry(.touchID, usable: false)
        try await waitForIcon(touchAppearance, host: host, description: "replacement unusable Touch instance")
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "touchid") }, afterSnapshotCount: observedImages,
            host: slotHost, description: "replacement unusable Touch instance: public icon value"
        )
        observedImages = recorder.snapshots().count
        OwnID.destroy(instanceName: instanceName)
        try await waitForIcon(faceAppearance, host: host, description: "destroyed instance")
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "faceid") }, afterSnapshotCount: observedImages,
            host: slotHost, description: "destroyed instance: public icon value"
        )
        observedImages = recorder.snapshots().count
    }

    @Test(arguments: ["boost", "login", "create"])
    func `Public icon output follows the current named instance and ignores old instance updates`(surface: String) async throws {
        guard #available(iOS 14, *) else { return }
        let first = uniqueInstanceName("icon-name-first")
        let second = uniqueInstanceName("icon-name-second")
        defer { OwnID.destroy(instanceName: first); OwnID.destroy(instanceName: second) }
        func initializeIcon(_ name: InstanceName, type: LABiometryType) throws {
            try initialize(instanceName: name)
            let container = try #require(OwnID.getInstanceContainer(name))
            container.register((any LocalInfo).self, instance: WidgetIconLocalInfo(
                biometryType: type, isBiometryUsable: true, biometryIconSystemName: "unrelated-system-icon"
            ))
        }
        try initializeIcon(first, type: .touchID)
        try initializeIcon(second, type: .faceID)
        let recorder = RuntimeSnapshotRecorder<Image>()
        let host = makeIconHost(surface: surface, instanceName: first, imageRecorder: recorder)
        defer { host.close() }
        _ = try await recorder.waitForSnapshot(matching: { $0 == Image(systemName: "touchid") }, host: host)
        let beforeSwitch = recorder.snapshots().count
        host.update(rootView: makeIconView(surface: surface, instanceName: second, imageRecorder: recorder))
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "faceid") }, afterSnapshotCount: beforeSwitch, host: host
        )
        try initializeIcon(first, type: .touchID)
        await host.settle(cycles: 20)
        #expect(recorder.snapshots().last == Image(systemName: "faceid"))
        let beforeReplacement = recorder.snapshots().count
        try initializeIcon(second, type: .touchID)
        _ = try await recorder.waitForSnapshot(
            matching: { $0 == Image(systemName: "touchid") }, afterSnapshotCount: beforeReplacement, host: host
        )
    }

    @Test(arguments: ["boost", "login", "create"])
    func `Public custom icon content retains explicit strings on a Touch device`(surface: String) async throws {
        let instanceName = uniqueInstanceName("custom-icon")
        defer { OwnID.destroy(instanceName: instanceName) }
        try initialize(instanceName: instanceName)
        let container = try #require(OwnID.getInstanceContainer(instanceName))
        container.register((any LocalInfo).self, instance: WidgetIconLocalInfo(
            biometryType: .touchID, isBiometryUsable: true, biometryIconSystemName: "faceid"
        ))
        let recorder = RuntimeSnapshotRecorder<String>()
        let strings = BoostWidgetStrings(skipPassword: "Caller label", or: "or")
        let customIcon: (Bool, Bool, @escaping () -> Void, String, Image) -> AnyView = { busy, enabled, _, label, _ in
            AnyView(RuntimeSnapshotProbe(snapshot: "custom|\(busy)|\(enabled)|" + label, recorder: recorder).frame(width: 44, height: 44))
        }
        let view: AnyView
        switch surface {
        case "login":
            view = AnyView(OwnIDLoginWidget(onLogin: { _ in }, instanceName: instanceName, widgetStrings: strings)
                .iconButton(customIcon).orText { Text($0) })
        case "create":
            view = AnyView(OwnIDCreatePasskeyWidget(
                onLogin: { _ in }, onNewPasskey: { _ in }, onReset: {}, instanceName: instanceName, widgetStrings: strings
            ).iconButton(customIcon).orText { Text($0) }.checkmark { EmptyView() })
        default:
            view = AnyView(OwnIDBoostButton(onClick: {}, isBusy: false, instanceName: instanceName, widgetStrings: strings)
                .iconButton(customIcon).orText { Text($0) }.checkmark { EmptyView() })
        }
        let host = SwiftUIRuntimeHost(rootView: view, size: CGSize(width: 220, height: 120))
        defer { host.close() }
        _ = try await waitForLabel(
            "custom|false|true|Caller label", recorder: recorder, host: host, description: "public custom \(surface) icon"
        )
        await host.settle(cycles: 10)
        #expect(recorder.snapshots().last == "custom|false|true|Caller label")
    }

    private func makeIconHost(
        surface: String,
        instanceName: InstanceName,
        referenceIcon: String? = nil,
        imageRecorder: RuntimeSnapshotRecorder<Image>? = nil
    ) -> SwiftUIRuntimeHost<AnyView> {
        SwiftUIRuntimeHost(
            rootView: makeIconView(surface: surface, instanceName: instanceName, referenceIcon: referenceIcon, imageRecorder: imageRecorder),
            size: CGSize(width: 220, height: 120)
        )
    }

    private func makeIconView(
        surface: String,
        instanceName: InstanceName,
        referenceIcon: String? = nil,
        imageRecorder: RuntimeSnapshotRecorder<Image>? = nil
    ) -> AnyView {
        let strings = BoostWidgetStrings(skipPassword: "Explicit label", or: "or")
        let theme = OwnIDTheme.capture(colorScheme: .light)
        let iconButton: (Bool, Bool, @escaping () -> Void, String, Image) -> OwnIDIconButtonView<RoundedRectangle> = { busy, enabled, action, label, candidate in
            imageRecorder?.record(candidate)
            return OwnIDIconButtonView(
                isBusy: busy, accessibilityLabel: label, isEnabled: enabled,
                icon: referenceIcon.map { Image(systemName: $0) } ?? candidate, action: action
            )
        }
        let view: AnyView
        switch surface {
        case "login":
            let widget = OwnIDLoginWidget(onLogin: { _ in }, theme: theme, instanceName: instanceName, widgetStrings: strings)
                .orText { Text($0) }
            view = referenceIcon == nil && imageRecorder == nil
                ? AnyView(widget) : AnyView(widget.iconButton(iconButton).orText { Text($0) })
        case "create":
            let widget = OwnIDCreatePasskeyWidget(
                onLogin: { _ in }, onNewPasskey: { _ in }, onReset: {}, theme: theme,
                instanceName: instanceName, widgetStrings: strings
            ).orText { Text($0) }.checkmark { EmptyView() }
            view = referenceIcon == nil && imageRecorder == nil
                ? AnyView(widget) : AnyView(widget.iconButton(iconButton).orText { Text($0) }.checkmark { EmptyView() })
        default:
            let button = OwnIDBoostButton(
                onClick: {}, isBusy: false, instanceName: instanceName, theme: theme, widgetStrings: strings
            ).orText { Text($0) }.checkmark { EmptyView() }
            view = referenceIcon == nil && imageRecorder == nil
                ? AnyView(button) : AnyView(button.iconButton(iconButton).orText { Text($0) }.checkmark { EmptyView() })
        }
        return AnyView(view.frame(width: 220, height: 120).background(Color.white).environment(\.colorScheme, .light))
    }

    private func iconAppearance<Content: View>(of host: SwiftUIRuntimeHost<Content>) -> Data {
        host.layout()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        host.host.view.layer.displayIfNeeded()
        return UIGraphicsImageRenderer(size: host.host.view.bounds.size, format: format).pngData { context in
            host.host.view.layer.render(in: context.cgContext)
        }
    }

    private func waitForIcon<Content: View>(
        _ expectedAppearance: Data,
        host: SwiftUIRuntimeHost<Content>,
        description: String
    ) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            await host.settle(cycles: 1)
            if iconAppearance(of: host) == expectedAppearance { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw SwiftUITestTimeoutError.timedOut(description)
    }

    private func makeHost(
        instanceName: InstanceName,
        recorder: RuntimeSnapshotRecorder<String>
    ) -> SwiftUIRuntimeHost<some View> {
        SwiftUIRuntimeHost(
            rootView: OwnIDBoostButton(
                onClick: {},
                isBusy: false,
                instanceName: instanceName,
                enabled: true,
                finished: false,
                showSpinner: false,
                iconButton: { _, _, _, accessibilityLabel, _ in
                    RuntimeSnapshotProbe(snapshot: accessibilityLabel, recorder: recorder)
                        .frame(width: 1, height: 1)
                },
                orText: { Text($0) },
                checkmark: { EmptyView() }
            ),
            size: CGSize(width: 220, height: 120)
        )
    }

    private func waitForLabel<Content: View>(
        _ label: String,
        recorder: RuntimeSnapshotRecorder<String>,
        host: SwiftUIRuntimeHost<Content>,
        afterSnapshotCount: Int = 0,
        description: String
    ) async throws -> String {
        try await recorder.waitForSnapshot(
            matching: { $0 == label },
            afterSnapshotCount: afterSnapshotCount,
            host: host,
            description: description
        )
    }

    private func initialize(instanceName: InstanceName) throws {
        let appID = "BoostStrings" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        OwnIDRootDIContainer.shared.injectRootDefaults()
        try OwnIDRootDIContainer.shared.initializeInstanceContainer(
            instanceName,
            configuration: NoNetworkOwnIDConfiguration(appID: appID)
        )
    }

    private func uniqueInstanceName(_ suffix: String) -> InstanceName {
        InstanceName(value: "BoostWidgetStringsRuntimeContractTests-\(suffix)-\(UUID().uuidString)")
    }
}

private struct NoNetworkOwnIDConfiguration: OwnIDConfiguration {
    let appID: String
    let env: OwnIDEnv = .prod
    let region: OwnIDRegion = .us

    // Forces SDK background configuration work to fail at URL resolution before creating a network request.
    let rootURL: String? = "http://["
}

// The lock protects stream continuation and waiter ownership across the provider's synchronous API and async callbacks.
private final class ControlledBoostWidgetStringsProvider: BoostWidgetStringsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var streamContinuation: AsyncStream<BoostWidgetStrings?>.Continuation?
    private var subscriptionWaiters: [CheckedContinuation<Void, Never>] = []
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []
    private var isTerminated = false

    func getStrings(params: BoostWidgetStringsParams) -> AsyncStream<BoostWidgetStrings?> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.markTerminated()
            }

            let waiters = lock.withLock {
                streamContinuation = continuation
                let waiters = subscriptionWaiters
                subscriptionWaiters.removeAll()
                return waiters
            }
            waiters.forEach { $0.resume() }
        }
    }

    func waitForSubscription() async {
        let isSubscribed = lock.withLock { streamContinuation != nil }
        guard !isSubscribed else { return }

        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if streamContinuation != nil {
                    return true
                }
                subscriptionWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func waitForTermination() async {
        let terminated = lock.withLock { isTerminated }
        guard !terminated else { return }

        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if isTerminated {
                    return true
                }
                terminationWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    @discardableResult
    func yield(_ strings: BoostWidgetStrings?) -> Bool {
        guard let continuation = lock.withLock({ streamContinuation }) else { return false }
        switch continuation.yield(strings) {
        case .enqueued:
            return true
        case .dropped:
            return false
        case .terminated:
            return false
        @unknown default:
            return false
        }
    }

    private func markTerminated() {
        let waiters = lock.withLock {
            isTerminated = true
            let waiters = terminationWaiters
            terminationWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }
}

private struct WidgetIconLocalInfo: LocalInfo {
    let modules: [(name: String, version: String)] = []
    let bundleID = "com.ownid.tests.icons"
    let appVersion = "1.0"
    let userAgent = "OwnIDSwiftUITests"
    let correlationId = "icon-tests"
    let isDebuggable = true
    var isSystemFidoCapable = true
    let biometryType: LABiometryType
    let isBiometryUsable: Bool
    var isBiometryEnrolled: Bool? = nil
    var isBiometryLockedOut: Bool? = nil
    let biometryLocalizedName: String? = "Misleading system name"
    let biometryIconSystemName: String?
    let isPasscodeSet: Bool? = true
}
