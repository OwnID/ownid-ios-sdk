import Foundation
import LocalAuthentication
import Testing

@testable import OwnIDCore

struct LocalInfoImplementationRuntimeTests {

    @Test func `Local info reports bundle metadata and fallback core module`() throws {
        let localInfo = LocalInfoImpl()
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        let expectedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let expectedSystemVersion = Self.currentSystemVersion()

        #expect(localInfo.bundleID == expectedBundleID)
        #expect(localInfo.appVersion == expectedAppVersion)
        #expect(localInfo.modules.isEmpty)
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/0.0.0 (iOS \(expectedSystemVersion); "))
        #expect(localInfo.userAgent.hasSuffix(" \(expectedBundleID)"))
        #expect(localInfo.userAgent.contains("; "))
        #expect(!localInfo.userAgent.contains("; )"))
        #expect(Self.isBase64URL(localInfo.correlationId))
        #expect(localInfo.correlationId.decodeBase64UrlSafe() != nil)
    }

    @Test func `Local info user agent includes exact current runtime device descriptor`() throws {
        let localInfo = LocalInfoImpl()
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        let expectedSystemVersion = Self.currentSystemVersion()
        let expectedDescriptor = Self.expectedRuntimeDeviceDescriptor()
        let expectedUserAgent = "OwnIDCore/0.0.0 (iOS \(expectedSystemVersion); \(expectedDescriptor)) \(expectedBundleID)"

        #expect(localInfo.userAgent == expectedUserAgent)
    }

    @Test func `Local info reports provided modules in user agent`() {
        let modules: [(name: String, version: String)] = [
            (name: "OwnIDSwiftUI", version: "4.0.0"),
            (name: "OwnIDCore", version: "4.0.0"),
            (name: "OwnIDWebBridge", version: "1.2.3"),
        ]

        let localInfo = LocalInfoImpl(modules: modules)

        #expect(localInfo.modules.map { $0.name } == modules.map { $0.name })
        #expect(localInfo.modules.map { $0.version } == modules.map { $0.version })
        #expect(localInfo.userAgent.hasPrefix("OwnIDCore/4.0.0 "))
        #expect(!localInfo.userAgent.contains("OwnIDCore/0.0.0"))
        #expect(localInfo.userAgent.contains("OwnIDSwiftUI/4.0.0"))
        #expect(localInfo.userAgent.contains("OwnIDWebBridge/1.2.3"))
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

    private static func expectedRuntimeDeviceDescriptor() -> String {
        let machineIdentifier = currentMachineIdentifier()
        let deviceName = expectedRuntimeModelName(machineIdentifier: machineIdentifier)

        if deviceName == machineIdentifier {
            return deviceName
        } else {
            return "\(deviceName); \(machineIdentifier)"
        }
    }

    private static func expectedRuntimeModelName(machineIdentifier: String) -> String {
        if ["i386", "x86_64", "arm64"].contains(machineIdentifier) {
            if let simulatorDeviceName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] {
                return "\(simulatorDeviceName.removingXcodeParallelClonePrefix()); simulator"
            } else {
                return "Simulator \(machineIdentifier)"
            }
        } else {
            return machineIdentifier
        }
    }

    private static func currentMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
}

extension String {
    fileprivate func removingXcodeParallelClonePrefix() -> String {
        replacingOccurrences(
            of: #"^Clone [0-9]+ of "#,
            with: "",
            options: .regularExpression
        )
    }
}
