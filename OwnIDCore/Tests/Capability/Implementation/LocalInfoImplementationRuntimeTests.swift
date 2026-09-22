import Foundation
import LocalAuthentication
import Testing

@testable import OwnIDCore

// Covers: INFO-RUNTIME-030, INFO-RUNTIME-040
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

    @Test func `Local info runtime flags are internally coherent`() {
        let localInfo = LocalInfoImpl()

        #if DEBUG
            #expect(localInfo.isDebuggable)
        #else
            #expect(!localInfo.isDebuggable)
        #endif

        if #available(iOS 16.0, *) {
            #expect(localInfo.isSystemFidoCapable)
        } else {
            #expect(!localInfo.isSystemFidoCapable)
        }

        #expect(!(localInfo.isFaceHardwarePresent && localInfo.isFingerprintHardwarePresent))
        if localInfo.isStrongBiometricEnabled {
            #expect(localInfo.isFaceHardwarePresent || localInfo.isFingerprintHardwarePresent)
        }
    }

    @Test func `Local info security flags match LAContext current runtime snapshot`() {
        let localInfo = LocalInfoImpl()
        let context = LAContext()
        let expectedStrongBiometricEnabled =
            context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let expectedBiometryType = context.biometryType
        let expectedDeviceSecured = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

        #expect(localInfo.isDeviceSecured == expectedDeviceSecured)
        #expect(localInfo.isFaceHardwarePresent == (expectedBiometryType == .faceID))
        #expect(localInfo.isFingerprintHardwarePresent == (expectedBiometryType == .touchID))
        #expect(localInfo.isStrongBiometricEnabled == expectedStrongBiometricEnabled)
        #expect(!(localInfo.isFaceHardwarePresent && localInfo.isFingerprintHardwarePresent))
        if localInfo.isStrongBiometricEnabled {
            #expect(localInfo.isDeviceSecured)
            #expect(localInfo.isFaceHardwarePresent || localInfo.isFingerprintHardwarePresent)
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
