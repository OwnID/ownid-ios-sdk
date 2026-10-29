import Foundation
import LocalAuthentication
import Testing

@testable import OwnIDCore

// Covers: INFO-RUNTIME-030
struct LocalInfoImplementationRuntimeTests {

    private static func expectedReleaseVersion() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sdk-version.xcconfig")
        let parts = try String(contentsOf: url, encoding: .utf8).split(separator: "=")
        try #require(parts.count == 2)
        return try #require(parts.last).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func `Local info reads bundled Core metadata without initializer inputs`() throws {
        let localInfo = LocalInfoImpl()
        let expectedVersion = try Self.expectedReleaseVersion()
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        let expectedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        #expect(localInfo.bundleID == expectedBundleID)
        #expect(localInfo.appVersion == expectedAppVersion)
        #expect(localInfo.modules.map { $0.name } == ["OwnIDCore"])
        #expect(localInfo.modules.map { $0.version } == [expectedVersion])
        #expect(Self.isBase64URL(localInfo.correlationId))
        #expect(localInfo.correlationId.decodeBase64UrlSafe() != nil)
    }

    @Test func `Local info user agent includes structured current runtime context`() throws {
        let localInfo = LocalInfoImpl()
        let expectedVersion = try Self.expectedReleaseVersion()
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        let expectedSystemVersion = Self.currentSystemVersion()
        let runtimePrefix = "OwnIDCore/\(expectedVersion) (iOS \(expectedSystemVersion); "
        let runtimeSuffix = ") \(expectedBundleID)"

        try #require(localInfo.userAgent.hasPrefix(runtimePrefix))
        try #require(localInfo.userAgent.hasSuffix(runtimeSuffix))

        let descriptor = String(localInfo.userAgent.dropFirst(runtimePrefix.count).dropLast(runtimeSuffix.count))
        #expect(!descriptor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        #if targetEnvironment(simulator)
            #expect(descriptor.localizedCaseInsensitiveContains("simulator"))
            #if arch(arm64)
                #expect(descriptor.contains("arm64"))
            #elseif arch(x86_64)
                #expect(descriptor.contains("x86_64"))
            #endif
        #endif
    }

    @Test(arguments: [
        ("SDK_VERSION = 4.2.0\n", "4.2.0"),
        ("// Release\r\n SDK_VERSION\t=\t12.34.56 \r\n", "12.34.56"),
        ("SDK_VERSION = 0.0.0", "0.0.0"),
        ("", "0.0.0"),
        ("OTHER_VERSION = 4.2.0", "0.0.0"),
        ("SDK_VERSION = ", "0.0.0"),
        ("SDK_VERSION = 4.2", "0.0.0"),
        ("SDK_VERSION = 4.2.0-beta", "0.0.0"),
        ("SDK_VERSION = 4.2.0\nSDK_VERSION = 4.2.1", "0.0.0"),
    ])
    func `Local info reads owned version resources and preserves modules when metadata is invalid`(contents: String, version: String) throws
    {
        let bundle = try Self.makeVersionBundle(contents: contents)
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }
        let localInfo = LocalInfoImpl(moduleResources: [("OwnIDCore", bundle), ("OwnIDSwiftUI", bundle)])

        #expect(localInfo.modules.map { $0.name } == ["OwnIDCore", "OwnIDSwiftUI"])
        #expect(localInfo.modules.map { $0.version } == [version, version])
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/\(version) "))
        #expect(localInfo.userAgent.contains(" OwnIDSwiftUI/\(version) "))
    }

    @Test func `Missing resource and missing bundle preserve module identities with unknown versions`() throws {
        let emptyBundle = try Self.makeVersionBundle(contents: nil)
        defer { try? FileManager.default.removeItem(at: emptyBundle.bundleURL) }
        let localInfo = LocalInfoImpl(moduleResources: [("OwnIDCore", nil), ("OwnIDSwiftUI", emptyBundle)])
        #expect(localInfo.modules.map { $0.name } == ["OwnIDCore", "OwnIDSwiftUI"])
        #expect(localInfo.modules.map { $0.version } == ["0.0.0", "0.0.0"])
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/0.0.0 "))
        #expect(localInfo.userAgent.contains(" OwnIDSwiftUI/0.0.0 "))
    }

    @Test func `Unreadable version text preserves the module with an unknown version`() throws {
        let bundle = try Self.makeVersionBundle(contents: nil)
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }
        try Data([0xFF]).write(to: bundle.bundleURL.appendingPathComponent("sdk-version.xcconfig"))
        let localInfo = LocalInfoImpl(moduleResources: [("OwnIDCore", bundle)])
        #expect(localInfo.modules.map { $0.name } == ["OwnIDCore"])
        #expect(localInfo.modules.map { $0.version } == ["0.0.0"])
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/0.0.0 "))
    }

    @Test func `Each module uses its own version resource and LocalInfo keeps its initial snapshot`() throws {
        let core = try Self.makeVersionBundle(contents: "SDK_VERSION = 4.2.0")
        let ui = try Self.makeVersionBundle(contents: "SDK_VERSION = 4.1.0")
        defer {
            try? FileManager.default.removeItem(at: core.bundleURL)
            try? FileManager.default.removeItem(at: ui.bundleURL)
        }
        let localInfo = LocalInfoImpl(moduleResources: [("OwnIDSwiftUI", ui), ("OwnIDCore", core)])
        try "SDK_VERSION = 9.9.9".write(to: ui.bundleURL.appendingPathComponent("sdk-version.xcconfig"), atomically: true, encoding: .utf8)
        #expect(localInfo.modules.map { $0.version } == ["4.1.0", "4.2.0"])
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/4.2.0 "))
        #expect(localInfo.userAgent.contains(" OwnIDSwiftUI/4.1.0 "))
    }

    private static func makeVersionBundle(contents: String?) throws -> Bundle {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OwnIDVersion-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": UUID().uuidString], format: .xml, options: 0)
        try info.write(to: url.appendingPathComponent("Info.plist"))
        if let contents {
            try contents.write(to: url.appendingPathComponent("sdk-version.xcconfig"), atomically: true, encoding: .utf8)
        }
        return try #require(Bundle(url: url))
    }

    @Test func `Local info reports OS level passkey support`() {
        let localInfo = LocalInfoImpl()
        if #available(iOS 16.0, *) {
            #expect(localInfo.isSystemFidoCapable)
        } else {
            #expect(!localInfo.isSystemFidoCapable)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 18))
    func `Legacy authentication metadata preserves unknown states and mechanism names`() {
        if #unavailable(iOS 18.0) {
            let localInfo = LocalInfoImpl()
            #expect(localInfo.isBiometryEnrolled == nil)
            #expect(localInfo.isBiometryLockedOut == nil)
            switch localInfo.biometryType {
            case .faceID:
                #expect(localInfo.biometryLocalizedName == "Face ID")
                #expect(localInfo.biometryIconSystemName == "faceid")
            case .touchID:
                #expect(localInfo.biometryLocalizedName == "Touch ID")
                #expect(localInfo.biometryIconSystemName == "touchid")
            default:
                #expect(localInfo.biometryLocalizedName == nil)
                #expect(localInfo.biometryIconSystemName == nil)
            }
        }
    }

    @Test func `SDK instances and reinitialization expose the same process snapshot`() async throws {
        try await withOwnIDRootStateTestLock {
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let firstName = InstanceName(value: "LocalInfoFirst\(suffix)")
            let secondName = InstanceName(value: "LocalInfoSecond\(suffix)")
            defer {
                OwnID.destroy(instanceName: firstName)
                OwnID.destroy(instanceName: secondName)
            }
            OwnID.initialize(instanceName: firstName) {
                $0.appID = "First\(suffix)"
                $0.rootURL = "https://127.0.0.1:9/local-info"
            }
            let first = OwnID.instance(instanceName: firstName).localInfo
            OwnID.initialize(instanceName: secondName) {
                $0.appID = "Second\(suffix)"
                $0.rootURL = "https://127.0.0.1:9/local-info"
            }
            let second = OwnID.instance(instanceName: secondName).localInfo
            OwnID.destroy(instanceName: firstName)
            OwnID.initialize(instanceName: firstName) {
                $0.appID = "First\(suffix)"
                $0.rootURL = "https://127.0.0.1:9/local-info"
            }
            let recreated = OwnID.instance(instanceName: firstName).localInfo

            for snapshot in [second, recreated] {
                #expect(snapshot.modules.map { $0.name } == first.modules.map { $0.name })
                #expect(snapshot.modules.map { $0.version } == first.modules.map { $0.version })
                #expect(snapshot.bundleID == first.bundleID)
                #expect(snapshot.appVersion == first.appVersion)
                #expect(snapshot.userAgent == first.userAgent)
                #expect(snapshot.correlationId == first.correlationId)
                #expect(snapshot.isDebuggable == first.isDebuggable)
                #expect(snapshot.isSystemFidoCapable == first.isSystemFidoCapable)
                #expect(snapshot.biometryType == first.biometryType)
                #expect(snapshot.isBiometryUsable == first.isBiometryUsable)
                #expect(snapshot.isBiometryEnrolled == first.isBiometryEnrolled)
                #expect(snapshot.isBiometryLockedOut == first.isBiometryLockedOut)
                #expect(snapshot.biometryLocalizedName == first.biometryLocalizedName)
                #expect(snapshot.biometryIconSystemName == first.biometryIconSystemName)
                #expect(snapshot.isPasscodeSet == first.isPasscodeSet)
            }
        }
    }

    private static func currentSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func isBase64URL(_ value: String) -> Bool {
        let allowedCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        return !value.isEmpty && value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

}
