import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

@Suite(.serialized)
struct OwnIDOptionalModuleDiscoveryRuntimeTests {

    @Test func `Missing optional UI module is logged and core initialization continues`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = InstanceName(value: "OwnIDOptionalModuleDiscoveryRuntimeTests-\(UUID().uuidString)")
            let logs = LogCapture()
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.logger { $0.level = .off }
            }

            #expect(NSClassFromString("OwnIDSwiftUI.OwnIDUIModule") == nil)

            OwnID.logger { logger in
                logger.level = .verbose
                logger.log { level, className, message, cause in
                    logs.append(
                        level: level,
                        className: className,
                        message: message,
                        hasCause: cause != nil,
                        causeDescription: cause?.localizedDescription
                    )
                }
            }

            OwnID.initialize(instanceName: instanceName) { configuration in
                configuration.appID = "CoreOnly\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                configuration.env = .uat
                configuration.region = .eu
                configuration.rootURL = "https://127.0.0.1:9/root"
            }

            let instance = try #require(OwnID.instanceIfPresent(instanceName: instanceName))
            let container = try #require(OwnID.getInstanceContainer(instanceName))

            #expect(instance.configuration.env == .uat)
            #expect(container.getOrNil(type: (any LocalInfo).self) != nil)
            #expect(container.getOrNil(type: (any LanguageTagsProvider).self) != nil)
            #expect(container.getOrNil(type: (any JSONCoder).self) != nil)
            #expect(container.getOrNil(type: (any LoginIDCollectUI).self) != nil)
            #expect(container.getOrNil(type: (any OperationUIContainer).self) == nil)

            let entries = logs.entries
            #expect(
                entries.contains {
                    $0.level == .verbose
                        && $0.className.contains("moduleLookup")
                        && $0.message.contains("Module class OwnIDSwiftUI.OwnIDUIModule not found")
                        && !$0.hasCause
                }
            )
            #expect(
                entries.contains {
                    $0.level == .info
                        && $0.className.contains("initializeInstanceContainer")
                        && $0.message.contains("No UI module injected. OperationUIContainer missing")
                        && !$0.hasCause
                }
            )
        }
    }

    @Test func `Bad optional module classes are logged skipped and valid modules inject once`() throws {
        let container = DIContainerImpl(scopeName: "optional-module-discovery")
        let logs = LogCapture()
        let recorder = OptionalModuleInjectionRecorder()
        container.register(OwnIDLogRouter.self, instance: testLogRouter(sink: logs, category: "ModuleDiscoveryTests"))
        container.register(OptionalModuleInjectionRecorder.self, instance: recorder)

        OwnIDModuleInjector.injectIntoInstanceContainer(
            container: container,
            classNames: [
                "Missing.OptionalModule",
                "NonConforming.OptionalModule",
                "Throwing.OptionalModule",
                "Recording.OptionalModule",
                "DuplicateRecording.OptionalModule",
            ],
            classResolver: { className in
                [
                    "NonConforming.OptionalModule": NonConformingOptionalModule.self,
                    "Throwing.OptionalModule": ThrowingOptionalModule.self,
                    "Recording.OptionalModule": RecordingOptionalModule.self,
                    "DuplicateRecording.OptionalModule": RecordingOptionalModule.self,
                ][className]
            }
        )

        #expect(recorder.injectionCount == 1)
        #expect(container.getOrNil(type: OptionalModuleInjectionMarker.self) == OptionalModuleInjectionMarker(name: "Recording"))

        let entries = logs.entries
        #expect(
            entries.contains {
                $0.level == .verbose
                    && $0.className.contains("moduleLookup")
                    && $0.message == "Module class Missing.OptionalModule not found"
                    && !$0.hasCause
            }
        )
        #expect(
            entries.contains {
                $0.level == .warn
                    && $0.className.contains("moduleLookup")
                    && $0.message == "Class NonConforming.OptionalModule does not conform to OwnIDModule"
                    && !$0.hasCause
            }
        )
        #expect(
            entries.contains {
                $0.level == .warn
                    && $0.className.contains("injectIntoInstanceContainer")
                    && $0.message.contains("Failed for:")
                    && $0.message.contains("ThrowingOptionalModule")
                    && $0.hasCause
            }
        )
    }
}

private final class NonConformingOptionalModule {}

private final class ThrowingOptionalModule: OwnIDModule {
    static func injectIntoInstanceContainer(container: any DIContainer) throws {
        throw OptionalModuleTestError(message: "optional module injection failed")
    }
}

private final class RecordingOptionalModule: OwnIDModule {
    static func injectIntoInstanceContainer(container: any DIContainer) throws {
        let recorder = try container.getOrThrow(type: OptionalModuleInjectionRecorder.self)
        recorder.recordInjection()
        container.register(OptionalModuleInjectionMarker.self, instance: OptionalModuleInjectionMarker(name: "Recording"))
    }
}

private final class OptionalModuleInjectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var injectionCount: Int {
        lock.withLock { count }
    }

    func recordInjection() {
        lock.withLock { count += 1 }
    }
}

private struct OptionalModuleInjectionMarker: Equatable, Sendable {
    let name: String
}

private struct OptionalModuleTestError: Error {
    let message: String
}
