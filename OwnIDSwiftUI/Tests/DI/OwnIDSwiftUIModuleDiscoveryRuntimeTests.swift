import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore
@_spi(OwnIDInternal) @testable import OwnIDSwiftUI

@Suite(.serialized)
struct OwnIDSwiftUIModuleDiscoveryRuntimeTests {

    @MainActor
    @Test func `SwiftUI product discovery registers runtime UI bindings after initialization`() throws {
        let instanceName = InstanceName(value: "OwnIDSwiftUIModuleDiscoveryRuntimeTests-\(UUID().uuidString)")
        defer { OwnID.destroy(instanceName: instanceName) }

        let discoveredModule = try #require(NSClassFromString("OwnIDSwiftUI.OwnIDUIModule") as? any OwnIDModule.Type)
        #expect(ObjectIdentifier(discoveredModule) == ObjectIdentifier(OwnIDUIModule.self))

        OwnID.initialize(instanceName: instanceName) { configuration in
            configuration.appID = "SwiftUIModule\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            configuration.env = .uat
            configuration.region = .eu
            configuration.rootURL = "https://127.0.0.1:9/root"
        }

        let container = try #require(OwnID.getInstanceContainer(instanceName))

        try assertSwiftUIModuleRuntimeBindings(in: container)
    }
}
