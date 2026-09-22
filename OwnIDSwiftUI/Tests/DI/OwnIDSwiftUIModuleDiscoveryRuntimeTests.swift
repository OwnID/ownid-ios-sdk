import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

// Covers: UI-PRESENT-040, INFO-RUNTIME-060
@Suite(.serialized)
struct OwnIDSwiftUIModuleDiscoveryRuntimeTests {

    @MainActor
    @Test func `SwiftUI product discovery registers runtime UI bindings after initialization`() throws {
        let instanceName = InstanceName(value: "OwnIDSwiftUIModuleDiscoveryRuntimeTests-\(UUID().uuidString)")
        defer { OwnID.destroy(instanceName: instanceName) }

        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = "SwiftUIModule\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            configuration.env = .uat
            configuration.region = .eu
            configuration.rootURL = "https://127.0.0.1:9/root"
        }

        let container = try #require(OwnID.getInstanceContainer(instanceName))
        let localInfo = try container.getOrThrow(type: (any LocalInfo).self)
        #expect(localInfo.modules.map { $0.name } == ["OwnIDCore", "OwnIDSwiftUI"])
        let coreVersion = try #require(localInfo.modules.first?.version)
        let configURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("sdk-version.xcconfig")
        let parts = try String(contentsOf: configURL, encoding: .utf8).split(separator: "=")
        try #require(parts.count == 2)
        let expectedVersion = try #require(parts.last).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(coreVersion == expectedVersion)
        #expect(localInfo.modules.map { $0.version } == [coreVersion, coreVersion])
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/\(coreVersion) "))
        #expect(localInfo.userAgent.contains(" OwnIDSwiftUI/\(coreVersion) "))

        try assertSwiftUIModuleRuntimeBindings(in: container)
    }
}
