import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: CFG-RUNTIME-020, CFG-RUNTIME-030, CFG-RUNTIME-040, CFG-RUNTIME-100, CFG-RUNTIME-110
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
            let container = try #require(OwnID.getInstanceContainer(instanceName))
            let firstNetwork = try #require(container.getOrNil(type: (any NetworkProtocol).self) as? NetworkImpl)
            let secondNetwork = try #require(container.getOrNil(type: (any NetworkProtocol).self) as? NetworkImpl)

            #expect(OwnID.instanceIfPresent(instanceName: instanceName) != nil)
            #expect(firstNetwork === secondNetwork)
            #expect(container.getOrNil(type: URLSession.self) == nil)
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

    @Test func `JSON null languages preserves the existing root language mode`() async throws {
        try await withOwnIDRootStateTestLock {
            let languageOwnerName = Self.uniqueInstanceName("json-null-language-owner")
            let jsonName = Self.uniqueInstanceName("json-null-language")
            defer {
                OwnID.destroy(instanceName: languageOwnerName)
                OwnID.destroy(instanceName: jsonName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: languageOwnerName) { configuration in
                configuration.appID = Self.uniqueAppID("LanguageOwner")
                configuration.languages = ["de-DE"]
            }
            let initialLanguageTags = try await Self.currentLanguageTags(for: languageOwnerName)
            #expect(initialLanguageTags == ["de-DE"])

            let jsonAppID = Self.uniqueAppID("JSONNullLanguage")
            OwnID.initializeFromJSON(instanceName: jsonName) { configuration in
                configuration.json = #"{"appId":"\#(jsonAppID)","languages":null}"#
            }

            #expect(OwnID.instanceIfPresent(instanceName: jsonName)?.configuration.appID == jsonAppID)
            let languageTagsAfterJSONInitialization = try await Self.currentLanguageTags(for: jsonName)
            #expect(languageTagsAfterJSONInitialization == ["de-DE"])
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

    @Test func `Conflicting identity preserves both instances and language`() async throws {
        try await withOwnIDRootStateTestLock {
            let ownerName = Self.uniqueInstanceName("identity-owner")
            let contenderName = Self.uniqueInstanceName("identity-contender")
            let sharedAppID = Self.uniqueAppID("Shared")
            let contenderAppID = Self.uniqueAppID("Contender")
            let sink = LogSink()
            defer {
                OwnID.destroy(instanceName: ownerName)
                OwnID.destroy(instanceName: contenderName)
                OwnID.setLanguage([])
                OwnID.logger { $0.level = .off }
            }

            OwnID.logger { logger in
                logger.level = .error
                logger.log { level, className, message, cause in
                    sink.append(level: level, className: className, message: message, hasCause: cause != nil)
                }
            }
            OwnID.initialize(instanceName: ownerName) { configuration in
                configuration.appID = sharedAppID
                configuration.env = .prod
                configuration.region = .us
                configuration.rootURL = "https://owner.example.com/root"
                configuration.languages = ["en-US"]
            }
            OwnID.initialize(instanceName: contenderName) { configuration in
                configuration.appID = contenderAppID
                configuration.env = .uat
                configuration.region = .eu
                configuration.rootURL = "https://contender.example.com/root"
                configuration.languages = ["de-DE"]
            }

            let ownerContainerID = try Self.containerID(#require(OwnID.getInstanceContainer(ownerName)))
            let contenderContainerID = try Self.containerID(#require(OwnID.getInstanceContainer(contenderName)))

            OwnID.initialize(instanceName: contenderName) { configuration in
                configuration.appID = sharedAppID
                configuration.env = .prod
                configuration.region = .us
                configuration.rootURL = "https://different-root.example.com/root"
                configuration.languages = ["ja-JP"]
            }

            let owner = OwnID.instance(instanceName: ownerName)
            let contender = OwnID.instance(instanceName: contenderName)

            #expect(try Self.containerID(#require(OwnID.getInstanceContainer(ownerName))) == ownerContainerID)
            #expect(try Self.containerID(#require(OwnID.getInstanceContainer(contenderName))) == contenderContainerID)
            #expect(owner.configuration.appID == sharedAppID)
            #expect(owner.configuration.rootURL == "https://owner.example.com/root")
            #expect(contender.configuration.appID == contenderAppID)
            #expect(contender.configuration.env == .uat)
            #expect(contender.configuration.region == .eu)
            #expect(contender.configuration.rootURL == "https://contender.example.com/root")
            #expect(try await Self.currentLanguageTags(for: contenderName) == ["de-DE"])
            #expect(
                sink.entries.contains {
                    $0.level == .error
                        && $0.className == "OwnID.initialize"
                        && $0.message.contains("Identity is already in use")
                        && $0.hasCause
                }
            )
        }
    }

    @Test func `Difference in any identity field permits coexistence`() async throws {
        try await withOwnIDRootStateTestLock {
            let names = (0..<4).map { Self.uniqueInstanceName("identity-\($0)") }
            let baseAppID = Self.uniqueAppID("Base")
            let otherAppID = Self.uniqueAppID("Other")
            defer {
                names.forEach { OwnID.destroy(instanceName: $0) }
                OwnID.setLanguage([])
            }

            Self.initialize(names[0], appID: baseAppID, env: .prod, region: .us)
            Self.initialize(names[1], appID: otherAppID, env: .prod, region: .us)
            Self.initialize(names[2], appID: baseAppID, env: .uat, region: .us)
            Self.initialize(names[3], appID: baseAppID, env: .prod, region: .eu)

            let containers = try names.map { try #require(OwnID.getInstanceContainer($0)) }
            let containerIDs = try containers.map(Self.containerID)

            #expect(Set(containerIDs).count == names.count)
            #expect(OwnID.instance(instanceName: names[1]).configuration.appID == otherAppID)
            #expect(OwnID.instance(instanceName: names[2]).configuration.env == .uat)
            #expect(OwnID.instance(instanceName: names[3]).configuration.region == .eu)
        }
    }

    @Test func `Concurrent conflicting initialization installs exactly one instance`() async throws {
        try await withOwnIDRootStateTestLock {
            let firstName = Self.uniqueInstanceName("concurrent-first")
            let secondName = Self.uniqueInstanceName("concurrent-second")
            let appID = Self.uniqueAppID("Concurrent")
            let probe = ConcurrentInitializationProbe()
            defer {
                probe.releaseFirstIdentityRead()
                OwnID.destroy(instanceName: firstName)
                OwnID.destroy(instanceName: secondName)
                OwnID.setLanguage([])
            }

            OwnIDRootDIContainer.shared.injectRootDefaults()
            let firstConfiguration = BlockingIdentityConfiguration(appID: appID, probe: probe)
            let secondConfiguration = try OwnIDConfigurationImpl(appID: appID)

            async let first = Self.initializeRootOnConcurrentQueue(
                instanceName: firstName,
                configuration: firstConfiguration
            )
            _ = try await probe.events.waitForFirst("first identity read starts") { $0 == .firstIdentityReadStarted }

            async let second = Self.initializeRootOnConcurrentQueue(
                instanceName: secondName,
                configuration: secondConfiguration,
                beforeInitialize: { probe.markSecondInitializationStarted() }
            )
            _ = try await probe.events.waitForFirst("second initialization starts") { $0 == .secondInitializationStarted }

            probe.releaseFirstIdentityRead()
            let outcomes = await [first, second]

            #expect(outcomes == [.success, .identityConflict(conflictingInstanceName: firstName)])
            let installedCount = [firstName, secondName].compactMap(OwnID.instanceIfPresent).count
            #expect(installedCount == 1)
        }
    }

    @Test func `Container stream emits current create replace and destroy states in order`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("stream-order")
            let firstAppID = Self.uniqueAppID("StreamFirst")
            let secondAppID = Self.uniqueAppID("StreamSecond")
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            var iterator = OwnID.getInstanceContainerStream(instanceName).makeAsyncIterator()
            let initialUpdate = try #require(await iterator.next())
            #expect(initialUpdate == nil)

            Self.initialize(instanceName, appID: firstAppID, env: .prod, region: .us)
            let firstUpdate = try #require(await iterator.next())
            let firstContainer = try #require(firstUpdate)
            let firstID = try Self.containerID(firstContainer)
            #expect(firstContainer.getOrNil(type: (any OwnIDConfiguration).self)?.appID == firstAppID)

            Self.initialize(instanceName, appID: secondAppID, env: .uat, region: .eu)
            let replacementUpdate = try #require(await iterator.next())
            let replacementContainer = try #require(replacementUpdate)
            let replacementID = try Self.containerID(replacementContainer)
            #expect(replacementContainer.getOrNil(type: (any OwnIDConfiguration).self)?.appID == secondAppID)

            OwnID.destroy(instanceName: instanceName)
            let destroyedUpdate = try #require(await iterator.next())

            #expect(replacementID != firstID)
            #expect(destroyedUpdate == nil)
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

    @Test func `Same identity replacement cancels old work and permits reuse after destroy`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("replace")
            let reuseName = Self.uniqueInstanceName("reuse")
            let appID = Self.uniqueAppID("Replacement")
            let cancelCalls = LockedCounter()
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.destroy(instanceName: reuseName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.rootURL = "https://first.example.com/root"
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
                    configuration.appID = appID
                    configuration.rootURL = "https://second.example.com/root"
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
            #expect(replacementInstance.configuration.appID == appID)
            #expect(replacementInstance.configuration.rootURL == "https://second.example.com/root")
            #expect(cancelCalls.value == 1)

            OwnID.destroy(instanceName: instanceName)
            Self.initialize(reuseName, appID: appID, env: .prod, region: .us)

            #expect(OwnID.instanceIfPresent(instanceName: instanceName) == nil)
            #expect(OwnID.instance(instanceName: reuseName).configuration.appID == appID)
        }
    }

    @Test func `Replacement offers destroy diagnostics through the old generation router`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("replacement-diagnostics")
            let appID = Self.uniqueAppID("ReplacementDiagnostics")
            let firstRootURL = try #require(URL(string: "https://lifecycle.ownid.test/old-\(UUID().uuidString)"))
            let secondRootURL = try #require(URL(string: "https://lifecycle.ownid.test/new-\(UUID().uuidString)"))
            let firstEventsURL = firstRootURL.appendingPathComponent("events")
            let secondEventsURL = secondRootURL.appendingPathComponent("events")
            let oldSink = LogSink()
            let newSink = LogSink()

            ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: firstEventsURL)
            ServerLoggerTestURLProtocol.register(.http(statusCode: 202, body: "{}"), for: secondEventsURL)
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.logger { $0.level = .off }
                ServerLoggerTestURLProtocol.unregister(firstEventsURL)
                ServerLoggerTestURLProtocol.unregister(secondEventsURL)
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.rootURL = "https://127.0.0.1:9/old"
            }
            let oldContainer = try #require(OwnID.getInstanceContainer(instanceName))
            let oldRouter = try #require(oldContainer.getOrNil(type: OwnIDLogRouter.self))
            let oldHarness = try makeRoutedServerLoggerHarness(
                instanceName: instanceName,
                rootURL: firstRootURL,
                taskScope: #require(oldContainer.getOrNil(type: TaskScope.self))
            )
            let oldServerLogger = oldHarness.logger
            oldContainer.register(
                (any OwnIDLogger).self,
                instance: LifecycleCapturingLogger(sink: oldSink)
            )
            oldContainer.register(ServerLogger.self, instance: oldServerLogger)
            await oldHarness.enableDebug()

            let oldMarker = "old-generation-\(UUID().uuidString)"
            oldRouter.logE(source: Self.self, prefix: "replacementDiagnostic", message: oldMarker)
            _ = try await withTestTimeout("old-generation diagnostic") {
                try await ServerLoggerTestURLProtocol.waitForRequest(to: firstEventsURL) {
                    serverLoggerRequestBodyData($0).map { String(decoding: $0, as: UTF8.self).contains(oldMarker) } == true
                }
            }

            OwnID.logger { logger in
                logger.level = .verbose
                logger.log { level, className, message, cause in
                    newSink.append(level: level, className: className, message: message, hasCause: cause != nil)
                }
            }
            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.rootURL = "https://127.0.0.1:9/new"
            }

            let newContainer = try #require(OwnID.getInstanceContainer(instanceName))
            let newRouter = try #require(newContainer.getOrNil(type: OwnIDLogRouter.self))
            let newHarness = try makeRoutedServerLoggerHarness(
                instanceName: instanceName,
                rootURL: secondRootURL,
                taskScope: #require(newContainer.getOrNil(type: TaskScope.self))
            )
            let newServerLogger = newHarness.logger
            newContainer.register(ServerLogger.self, instance: newServerLogger)
            await newHarness.enableDebug()
            let newMarker = "new-generation-\(UUID().uuidString)"
            newRouter.logE(source: Self.self, prefix: "replacementDiagnostic", message: newMarker)
            _ = try await withTestTimeout("new-generation diagnostic") {
                try await ServerLoggerTestURLProtocol.waitForRequest(to: secondEventsURL) {
                    serverLoggerRequestBodyData($0).map { String(decoding: $0, as: UTF8.self).contains(newMarker) } == true
                }
            }

            #expect(oldRouter !== newRouter)
            #expect(oldServerLogger !== newServerLogger)
            #expect(oldContainer.getOrNil(type: OwnIDLogRouter.self) === oldRouter)
            #expect(oldContainer.getOrNil(type: ServerLogger.self) === oldServerLogger)
            #expect(
                oldSink.entries.contains {
                    $0.level == .debug
                        && $0.message == "Instance destroyed: \(instanceName.value)"
                }
            )
            #expect(newSink.entries.allSatisfy { $0.message != "Instance destroyed: \(instanceName.value)" })
            #expect(
                ServerLoggerTestURLProtocol.requests(for: firstEventsURL).allSatisfy {
                    serverLoggerRequestBodyData($0).map { !String(decoding: $0, as: UTF8.self).contains(newMarker) } == true
                }
            )
            #expect(
                ServerLoggerTestURLProtocol.requests(for: secondEventsURL).allSatisfy {
                    serverLoggerRequestBodyData($0).map { !String(decoding: $0, as: UTF8.self).contains(oldMarker) } == true
                }
            )
        }
    }

    @Test(arguments: FlowInstanceInvalidation.allCases)
    func `Invalidated instance eventually releases discarded state`(_ invalidation: FlowInstanceInvalidation) async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("release-\(invalidation.testDescription)")
            let appID = Self.uniqueAppID("Release")
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            let probes = try Self.invalidateInstanceAndDropHandles(
                invalidation,
                instanceName: instanceName,
                appID: appID
            )

            try await Self.assertEventuallyReleased("old instance container", probe: probes.oldContainerReleased)
            try await Self.assertEventuallyReleased("app provider callback", probe: probes.providerCallbackReleased)
        }
    }

    @Test(arguments: FlowInstanceInvalidation.allCases)
    func `Flow controllers created from invalidated instance entries settle canceled`(
        _ invalidation: FlowInstanceInvalidation
    ) async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = Self.uniqueInstanceName("invalidated-flow-\(invalidation.testDescription)")
            let appID = Self.uniqueAppID("InvalidatedFlow")
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.setLanguage([])
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.rootURL = "https://first.example.com/root"
            }

            let instance = OwnID.instance(instanceName: instanceName)
            let boostLoginEntry = instance.flows.boost.login
            let boostCreatePasskeyEntry = instance.flows.boost.createPasskey
            let eliteEntry = instance.flows.elite
            let passkeyEnrollEntry = instance.headless.passkeys.enroll

            switch invalidation {
            case .destroy:
                OwnID.destroy(instanceName: instanceName)
            case .sameNameReplacement:
                OwnID.initialize(instanceName: instanceName) { configuration in
                    configuration.appID = appID
                    configuration.rootURL = "https://second.example.com/root"
                }
            }

            let boostLoginController = boostLoginEntry.start()
            let boostCreatePasskeyController = boostCreatePasskeyEntry.start()
            let eliteController = eliteEntry.start()
            let passkeyEnrollController = passkeyEnrollEntry.start()

            try await Self.assertInvalidatedFlowSettlesCanceled(
                "Boost login after \(invalidation.testDescription)",
                whenSettled: { await boostLoginController.whenSettled() },
                abort: { boostLoginController.abort(reason: $0) }
            )
            try await Self.assertInvalidatedFlowSettlesCanceled(
                "Boost create-passkey after \(invalidation.testDescription)",
                whenSettled: { await boostCreatePasskeyController.whenSettled() },
                abort: { boostCreatePasskeyController.abort(reason: $0) }
            )
            try await Self.assertInvalidatedFlowSettlesCanceled(
                "Elite after \(invalidation.testDescription)",
                whenSettled: { await eliteController.whenSettled() },
                abort: { eliteController.abort(reason: $0) }
            )
            try await Self.assertInvalidatedFlowSettlesCanceled(
                "passkey enroll after \(invalidation.testDescription)",
                whenSettled: { await passkeyEnrollController.whenSettled() },
                abort: { passkeyEnrollController.abort(reason: $0) }
            )
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

    private static func invalidateInstanceAndDropHandles(
        _ invalidation: FlowInstanceInvalidation,
        instanceName: InstanceName,
        appID: String
    ) throws -> LifecycleReleaseProbes {
        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = appID
            configuration.rootURL = "https://first.example.com/root"
        }

        let providerCallbackSentinel = LifecycleReleaseSentinel()
        let handle = OwnID.instance(instanceName: instanceName)
        _ = handle.setProviders { registrar in
            registrar.sessionCreate { builder in
                builder.create { [providerCallbackSentinel] _ in
                    _ = providerCallbackSentinel
                    return .success(SessionOutput(session: "unused"))
                }
            }
        }

        let oldContainer = try #require(OwnID.getInstanceContainer(instanceName) as? DIContainerImpl)
        let probes = LifecycleReleaseProbes(
            oldContainerReleased: { [weak oldContainer] in oldContainer == nil },
            providerCallbackReleased: { [weak providerCallbackSentinel] in providerCallbackSentinel == nil }
        )

        switch invalidation {
        case .destroy:
            OwnID.destroy(instanceName: instanceName)
        case .sameNameReplacement:
            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = appID
                configuration.rootURL = "https://second.example.com/root"
            }
        }

        return probes
    }

    private static func assertEventuallyReleased(
        _ description: String,
        probe: @escaping @Sendable () -> Bool,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws {
        for _ in 0..<300 {
            if probe() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(probe(), "Expected \(description) to be released", sourceLocation: sourceLocation)
    }

    private static func assertInvalidatedFlowSettlesCanceled<Success: Sendable, Failure: FlowFailure>(
        _ description: String,
        whenSettled: @escaping @Sendable () async -> FlowResult<Success, Failure>,
        abort: @escaping @Sendable (Reason) -> Void,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) async throws {
        let result = try await withTestTimeout("\(description) settles") {
            await whenSettled()
        }
        let reason = try requireCancellation(result, sourceLocation: sourceLocation)
        guard case .systemError = reason else {
            Issue.record("Expected system-error cancellation, got \(reason)", sourceLocation: sourceLocation)
            return
        }

        abort(.userClose(details: "late abort after lifecycle cancellation"))

        let cachedResult = try await withTestTimeout("\(description) returns its cached result") {
            await whenSettled()
        }
        let cachedReason = try requireCancellation(cachedResult, sourceLocation: sourceLocation)
        guard case .systemError = cachedReason else {
            Issue.record("Expected cached system-error cancellation, got \(cachedReason)", sourceLocation: sourceLocation)
            return
        }
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

    private static func initialize(
        _ instanceName: InstanceName,
        appID: String,
        env: OwnIDEnv,
        region: OwnIDRegion
    ) {
        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = appID
            configuration.env = env
            configuration.region = region
        }
    }

    private static func initializeRootOnConcurrentQueue(
        instanceName: InstanceName,
        configuration: any OwnIDConfiguration,
        beforeInitialize: @escaping @Sendable () -> Void = {}
    ) async -> RootInitializationOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                beforeInitialize()
                do {
                    try OwnIDRootDIContainer.shared.initializeInstanceContainer(
                        instanceName,
                        configuration: configuration
                    )
                    continuation.resume(returning: .success)
                } catch let error as IdentityConflictError {
                    continuation.resume(
                        returning: .identityConflict(conflictingInstanceName: error.conflictingInstanceName)
                    )
                } catch {
                    continuation.resume(returning: .unexpectedError(String(describing: error)))
                }
            }
        }
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

    private final class LifecycleCapturingLogger: OwnIDLogger, @unchecked Sendable {
        let level: LogLevel = .verbose
        let category = "OwnID-Lifecycle-Test"
        private let sink: LogSink

        init(sink: LogSink) {
            self.sink = sink
        }

        func log(level: LogLevel, className: String, message: String, cause: (any Error)?) {
            guard isEnabled(level) else { return }
            sink.append(level: level, className: className, message: message, hasCause: cause != nil)
        }
    }
}

enum FlowInstanceInvalidation: CaseIterable, CustomTestStringConvertible, Sendable {
    case destroy
    case sameNameReplacement

    var testDescription: String {
        switch self {
        case .destroy: "destroy"
        case .sameNameReplacement: "same-name replacement"
        }
    }
}

private enum ConcurrentInitializationEvent: Equatable, Sendable {
    case firstIdentityReadStarted
    case secondInitializationStarted
}

private enum RootInitializationOutcome: Equatable, Sendable {
    case success
    case identityConflict(conflictingInstanceName: InstanceName)
    case unexpectedError(String)
}

private final class ConcurrentInitializationProbe: @unchecked Sendable {
    let events = AsyncSignalRecorder<ConcurrentInitializationEvent>()

    // @unchecked Sendable: the blocking state is protected by releaseCondition.
    private let releaseCondition = NSCondition()
    private var isFirstIdentityReadReleased = false

    func blockFirstIdentityRead() {
        events.append(.firstIdentityReadStarted)

        releaseCondition.lock()
        while !isFirstIdentityReadReleased {
            releaseCondition.wait()
        }
        releaseCondition.unlock()
    }

    func markSecondInitializationStarted() {
        events.append(.secondInitializationStarted)
    }

    func releaseFirstIdentityRead() {
        releaseCondition.lock()
        isFirstIdentityReadReleased = true
        releaseCondition.broadcast()
        releaseCondition.unlock()
    }
}

private final class BlockingIdentityConfiguration: OwnIDConfiguration, @unchecked Sendable {
    private let storedAppID: String
    private let probe: ConcurrentInitializationProbe

    var appID: String {
        probe.blockFirstIdentityRead()
        return storedAppID
    }

    let env: OwnIDEnv = .prod
    let region: OwnIDRegion = .us
    let rootURL: String? = nil

    init(appID: String, probe: ConcurrentInitializationProbe) {
        self.storedAppID = appID
        self.probe = probe
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

private struct LifecycleReleaseProbes: Sendable {
    let oldContainerReleased: @Sendable () -> Bool
    let providerCallbackReleased: @Sendable () -> Bool
}

private final class LifecycleReleaseSentinel: Sendable {}
