import Foundation
import SwiftUI
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-300
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
                iconButton: { _, _, _, accessibilityLabel in
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
