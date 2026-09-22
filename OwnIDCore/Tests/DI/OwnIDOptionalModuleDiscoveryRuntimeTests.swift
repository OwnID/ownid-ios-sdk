import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: SPI-100, UI-PRESENT-050
@Suite(.serialized)
struct OwnIDOptionalModuleDiscoveryRuntimeTests {

    @Test func `Every discovered module supplies its resource descriptor without injecting dependencies`() throws {
        let infos = OwnIDModuleInjector.moduleResources(
            classNames: ["missing", "recording", "resource", "duplicate", "unrelated"],
            classResolver: {
                let classes: [String: AnyClass] = [
                    "recording": RecordingOptionalModule.self,
                    "resource": ResourceOptionalModule.self,
                    "duplicate": ResourceOptionalModule.self,
                    "unrelated": NonConformingOptionalModule.self,
                ]
                return classes[$0]
            }
        )

        try #require(infos.count == 2)
        #expect(infos.map { $0.name } == ["OwnIDRecordingModule", "OwnIDTestModule"])
        #expect(infos[0].bundle == nil)
        #expect(infos[1].bundle == Bundle.main)
    }

    @Test func `Missing optional SDK modules are logged and core initialization continues`() async throws {
        try await withOwnIDRootStateTestLock {
            let instanceName = InstanceName(value: "OwnIDOptionalModuleDiscoveryRuntimeTests-\(UUID().uuidString)")
            let logs = LogCapture()
            defer {
                OwnID.destroy(instanceName: instanceName)
                OwnID.logger { $0.level = .off }
            }

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
            #expect(container.getOrNil(type: (any EmailVerificationUI).self) != nil)
            #expect(container.getOrNil(type: (any PhoneVerificationUI).self) != nil)
            #expect(container.getOrNil(type: (any OperationUIContainer).self) == nil)

            let entries = logs.entries
            #expect(
                entries.contains {
                    $0.level == .verbose
                        && $0.className.contains("moduleLookup")
                        && $0.message.contains("OwnIDSwiftUIModule")
                        && !$0.hasCause
                }
            )
            #expect(
                entries.contains {
                    $0.level == .verbose
                        && $0.className.contains("moduleLookup")
                        && $0.message.contains("OwnIDReactNativeCoreModule")
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
                let classes: [String: AnyClass] = [
                    "NonConforming.OptionalModule": NonConformingOptionalModule.self,
                    "Throwing.OptionalModule": ThrowingOptionalModule.self,
                    "Recording.OptionalModule": RecordingOptionalModule.self,
                    "DuplicateRecording.OptionalModule": RecordingOptionalModule.self,
                ]
                return classes[className]
            }
        )

        #expect(recorder.injectionCount == 1)
        #expect(container.getOrNil(type: OptionalModuleInjectionMarker.self) == OptionalModuleInjectionMarker(name: "Recording"))

        let entries = logs.entries
        #expect(
            entries.contains {
                $0.level == .verbose
                    && $0.className.contains("moduleLookup")
                    && $0.message.contains("Missing.OptionalModule")
                    && !$0.hasCause
            }
        )
        #expect(
            entries.contains {
                $0.level == .warn
                    && $0.className.contains("moduleLookup")
                    && $0.message.contains("NonConforming.OptionalModule")
                    && !$0.hasCause
            }
        )
        #expect(
            entries.contains {
                $0.level == .warn
                    && $0.className.contains("injectIntoInstanceContainer")
                    && $0.message.contains("ThrowingOptionalModule")
                    && $0.hasCause
            }
        )
    }
}

private final class NonConformingOptionalModule {}

private final class ResourceOptionalModule: OwnIDModule {
    static var moduleResources: (name: String, bundle: Bundle?) { ("OwnIDTestModule", .main) }

    static func injectIntoInstanceContainer(container: any DIContainer) throws {
        Issue.record("Reading module metadata must not inject dependencies")
    }
}

private final class ThrowingOptionalModule: OwnIDModule {
    static var moduleResources: (name: String, bundle: Bundle?) { ("OwnIDThrowingModule", nil) }

    static func injectIntoInstanceContainer(container: any DIContainer) throws {
        throw OptionalModuleTestError(message: "optional module injection failed")
    }
}

private final class RecordingOptionalModule: OwnIDModule {
    static var moduleResources: (name: String, bundle: Bundle?) { ("OwnIDRecordingModule", nil) }

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
