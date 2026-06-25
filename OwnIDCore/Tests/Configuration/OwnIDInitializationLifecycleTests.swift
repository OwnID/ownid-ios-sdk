import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@Suite(.serialized)
struct OwnIDInitializationLifecycleTests {

    @Test func `Programmatic initialization creates usable instance with root defaults`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("valid")
            let appID = Self.uniqueAppID("Valid")
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.env = .uat
                configuration.region = .eu
                configuration.rootURL = "https://127.0.0.1:9/root?token=secret#fragment"
                configuration.languages = ["en-US", "fr-FR"]
            }

            let instance = OwnID.instance(instanceName: instanceName)

            #expect(OwnID.instanceIfPresent(instanceName: instanceName) != nil)
            #expect(instance.configuration.appID == appID)
            #expect(instance.configuration.env == .uat)
            #expect(instance.configuration.region == .eu)
            #expect(instance.configuration.rootURL == "https://127.0.0.1:9/root")
            #expect(instance.localInfo.bundleID == (Bundle.main.bundleIdentifier ?? "com.unknown.app"))
            #expect(!instance.localInfo.userAgent.isEmpty)
            let languageTags = try await Self.currentLanguageTags(for: instanceName)
            #expect(languageTags == ["en-US", "fr-FR"])
        }
    }

    @Test func `Invalid programmatic initialization preserves existing instance state`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("invalid")
            let appID = Self.uniqueAppID("Stable")
            let sink = LogSink()
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
                OwnID.logger { $0.level = .off }
            }

            OwnID.logger { logger in
                logger.level = .error
                logger.log { level, className, message, cause in
                    sink.append(level: level, className: className, message: message, hasCause: cause != nil)
                }
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.env = .prod
                configuration.region = .us
                configuration.rootURL = "https://127.0.0.1:9/base"
                configuration.languages = ["de-DE"]
            }
            let beforeContainer = try #require(OwnID.getInstanceContainer(instanceName))
            let beforeID = try Self.containerID(beforeContainer)

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = ""
                configuration.env = .uat
                configuration.region = .eu
                configuration.rootURL = "https://127.0.0.1:9/mutated"
                configuration.languages = ["ja-JP"]
            }

            let afterContainer = try #require(OwnID.getInstanceContainer(instanceName))
            let instance = OwnID.instance(instanceName: instanceName)

            let afterID = try Self.containerID(afterContainer)
            #expect(afterID == beforeID)
            #expect(instance.configuration.appID == appID)
            #expect(instance.configuration.env == .prod)
            #expect(instance.configuration.region == .us)
            #expect(instance.configuration.rootURL == "https://127.0.0.1:9/base")
            let languageTags = try await Self.currentLanguageTags(for: instanceName)
            #expect(languageTags == ["de-DE"])
            #expect(
                sink.entries.contains {
                    $0.level == .error
                        && $0.className == "OwnID.initialize"
                        && $0.message.contains("Configuration creation failed")
                        && $0.hasCause
                }
            )
        }
    }

    @Test func `Destroy is idempotent removes instance and cancels owned task`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("destroy")
            let appID = Self.uniqueAppID("Destroy")
            let cancelCalls = LockedCounter()
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
            }

            var iterator = OwnID.getInstanceContainerStream(instanceName).makeAsyncIterator()
            let currentContainer = try #require(await iterator.next())
            let container = try #require(currentContainer)
            let taskScope = try #require(container.getOrNil(type: TaskScope.self))

            let task = try await confirmation("owned task starts and is canceled by destroy", expectedCount: 2) { confirm in
                let task = try #require(
                    taskScope.spawn(onCancel: {
                        _ = cancelCalls.increment()
                        confirm()
                    }) {
                        confirm()
                        await waitForTaskCancellation()
                    }
                )

                OwnID.destroy(instanceName: instanceName)
                OwnID.destroy(instanceName: instanceName)
                await task.value

                return task
            }
            await task.value

            let destroyedContainer = try #require(await iterator.next())
            #expect(destroyedContainer == nil)
            #expect(OwnID.instanceIfPresent(instanceName: instanceName) == nil)
            #expect(OwnID.getInstanceContainer(instanceName) == nil)
            #expect(cancelCalls.value == 1)
        }
    }

    @Test func `Same name replacement cancels old owned task and installs new container`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("replace")
            let firstAppID = Self.uniqueAppID("First")
            let secondAppID = Self.uniqueAppID("Second")
            let cancelCalls = LockedCounter()
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = firstAppID
            }

            var iterator = OwnID.getInstanceContainerStream(instanceName).makeAsyncIterator()
            let currentContainer = try #require(await iterator.next())
            let oldContainer = try #require(currentContainer)
            let oldID = try Self.containerID(oldContainer)
            let oldTaskScope = try #require(oldContainer.getOrNil(type: TaskScope.self))

            let oldTask = try await confirmation("old owned task starts and is canceled by replacement", expectedCount: 2) { confirm in
                let task = try #require(
                    oldTaskScope.spawn(onCancel: {
                        _ = cancelCalls.increment()
                        confirm()
                    }) {
                        confirm()
                        await waitForTaskCancellation()
                    }
                )

                OwnID.initialize(instanceName: instanceName) { configuration in
                    configuration.appID = secondAppID
                    configuration.env = .uat
                }
                await task.value

                return task
            }
            await oldTask.value

            let replacementContainerUpdate = try #require(await iterator.next())
            let replacementContainer = try #require(replacementContainerUpdate)
            let replacementInstance = OwnID.instance(instanceName: instanceName)

            let replacementID = try Self.containerID(replacementContainer)
            #expect(replacementID != oldID)
            #expect(replacementInstance.configuration.appID == secondAppID)
            #expect(replacementInstance.configuration.env == .uat)
            #expect(cancelCalls.value == 1)
        }
    }

    @Test func `Reinitialized handles resolve against current instance without stale scoped state`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("stale")
            let firstAppID = Self.uniqueAppID("First")
            let secondAppID = Self.uniqueAppID("Second")
            let thirdAppID = Self.uniqueAppID("Third")
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = firstAppID
            }
            let firstHandle = OwnID.instance(instanceName: instanceName)
            let firstContainer = try Self.container(from: firstHandle)
            let firstContainerID = try Self.containerID(firstContainer)

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = secondAppID
                configuration.env = .uat
            }

            let secondHandle = OwnID.instance(instanceName: instanceName)
            let secondContainer = try Self.container(from: secondHandle)
            let secondContainerID = try Self.containerID(secondContainer)

            #expect(secondContainerID != firstContainerID)
            #expect(secondHandle.configuration.appID == secondAppID)
            #expect(secondHandle.configuration.env == .uat)

            let firstStaleRegistry = try await Self.installScopedState(
                on: firstHandle,
                accessToken: "first-stale-token",
                providerSession: "first-stale-session",
                operationID: "first-stale-operation"
            )
            let firstStaleContainer = try Self.container(from: firstHandle)

            #expect(try Self.containerID(firstStaleContainer) == firstContainerID)
            try await Self.assertScopedState(
                in: firstStaleContainer,
                accessToken: "first-stale-token",
                operationID: "first-stale-operation"
            )
            try await Self.assertNoScopedStateLeaked(in: secondContainer)
            #expect(secondContainer.getOrNil(type: (any OperationRegistry).self) as? OperationRegistryImpl !== firstStaleRegistry)

            let secondRegistry = try await Self.installScopedState(
                on: secondHandle,
                accessToken: "second-token",
                providerSession: "second-session",
                operationID: "second-operation"
            )
            try await Self.assertScopedState(in: secondContainer, accessToken: "second-token", operationID: "second-operation")

            OwnID.destroy(instanceName: instanceName)
            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = thirdAppID
                configuration.env = .prod
            }

            let thirdHandle = OwnID.instance(instanceName: instanceName)
            let thirdContainer = try Self.container(from: thirdHandle)

            #expect(try Self.containerID(Self.container(from: secondHandle)) == secondContainerID)
            #expect(thirdHandle.configuration.appID == thirdAppID)
            #expect(try Self.containerID(thirdContainer) != secondContainerID)
            try await Self.assertScopedState(in: secondContainer, accessToken: "second-token", operationID: "second-operation")
            try await Self.assertNoScopedStateLeaked(in: thirdContainer)
            #expect(thirdContainer.getOrNil(type: (any OperationRegistry).self) as? OperationRegistryImpl !== secondRegistry)
        }
    }

    @discardableResult
    private static func installScopedState(
        on handle: any OwnIDInstance,
        accessToken: String,
        providerSession: String,
        operationID: String
    ) async throws -> OperationRegistryImpl {
        _ = handle.setContext { builder in
            builder.authz = .fromToken(accessToken)
            builder.accountDisplayName = providerSession
        }
        _ = handle.setProviders { registrar in
            registrar.sessionCreate { builder in
                builder.create { _ in .success(SessionOutput(session: providerSession)) }
            }
        }

        let container = try container(from: handle)
        let registry = try #require(container.getOrNil(type: (any OperationRegistry).self) as? OperationRegistryImpl)
        await MainActor.run {
            registry.register(controller: StaleHandleOperationController(id: operationID))
        }
        return registry
    }

    private static func assertScopedState(
        in container: any DIContainer,
        accessToken: String,
        operationID: String,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws {
        let context = try #require(container.getOrNil(type: Context.self), sourceLocation: sourceLocation)
        #expect(context.accessToken?.token == accessToken, sourceLocation: sourceLocation)
        #expect(container.getOrNil(type: (any SessionCreate).self) != nil, sourceLocation: sourceLocation)

        let registry = try #require(
            container.getOrNil(type: (any OperationRegistry).self) as? OperationRegistryImpl,
            sourceLocation: sourceLocation
        )
        await MainActor.run {
            #expect(registry.operations.keys.contains(OperationID(type: .sessionCreation, id: operationID)), sourceLocation: sourceLocation)
        }
    }

    private static func assertNoScopedStateLeaked(
        in container: any DIContainer,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws {
        #expect(container.getOrNil(type: Context.self) == nil, sourceLocation: sourceLocation)
        #expect(container.getOrNil(type: (any SessionCreate).self) == nil, sourceLocation: sourceLocation)

        let registry = try #require(
            container.getOrNil(type: (any OperationRegistry).self) as? OperationRegistryImpl,
            sourceLocation: sourceLocation
        )
        await MainActor.run {
            #expect(registry.operations.isEmpty, sourceLocation: sourceLocation)
        }
    }

    private static func currentLanguageTags(for instanceName: InstanceName) async throws -> [String] {
        let container = try #require(OwnID.getInstanceContainer(instanceName))
        let provider = try #require(container.getOrNil(type: (any LanguageTagsProvider).self))
        var iterator = provider.languageTags.makeAsyncIterator()
        let tags = try #require(await iterator.next())
        return tags.map(\.tagString)
    }

    private static func containerID(_ container: any DIContainer) throws -> ObjectIdentifier {
        ObjectIdentifier(try #require(container as? DIContainerImpl))
    }

    private static func container(from handle: any OwnIDInstance) throws -> any DIContainer {
        try #require((handle as? OwnIDInstanceImpl)?.container)
    }

    private static func uniqueInstanceName(_ prefix: String) -> InstanceName {
        InstanceName(value: "OwnIDInitializationLifecycleTests-\(prefix)-\(UUID().uuidString)")
    }

    private static func uniqueAppID(_ prefix: String) -> String {
        prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private final class LogSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [LogEntry] = []

        var entries: [LogEntry] {
            lock.withLock { storage }
        }

        func append(level: LogLevel, className: String, message: String, hasCause: Bool) {
            lock.withLock {
                storage.append(LogEntry(level: level, className: className, message: message, hasCause: hasCause))
            }
        }
    }

    private struct LogEntry: Equatable, Sendable {
        let level: LogLevel
        let className: String
        let message: String
        let hasCause: Bool
    }
}

private final class StaleHandleOperationController: OperationController, @unchecked Sendable {
    typealias Success = Void
    typealias Failure = StaleHandleOperationFailure

    let operationID: OperationID

    init(id: String) {
        operationID = OperationID(type: .sessionCreation, id: id)
    }

    func abort(reason: Reason) {}

    func whenSettled() async -> OperationResult<Void, StaleHandleOperationFailure> {
        .canceled(.userClose())
    }
}

private struct StaleHandleOperationFailure: OperationFailure {
    let errorCode: ErrorCode = .unknown
    let message = "stale handle test failure"
}
