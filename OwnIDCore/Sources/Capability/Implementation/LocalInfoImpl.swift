import Foundation
import LocalAuthentication

internal struct LocalInfoImpl: LocalInfo {
    let modules: [(name: String, version: String)]
    let bundleID: String
    let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    let userAgent: String
    let correlationId: String = Data.secureRandom().encodeToBase64UrlSafe()

    #if DEBUG
        let isDebuggable = true
    #else
        let isDebuggable = false
    #endif

    let isSystemFidoCapable: Bool
    let isDeviceSecured: Bool
    let isFaceHardwarePresent: Bool
    let isFingerprintHardwarePresent: Bool
    let isStrongBiometricEnabled: Bool

    init(modules: [(name: String, version: String)] = []) {
        self.modules = modules

        let appBundleID = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        self.bundleID = appBundleID
        let rawMachineIdentifier = DeviceInfo.machineIdentifier
        let core = modules.first { $0.name.lowercased() == "ownidcore" }
            .map { "\($0.name)/\($0.version)" }
        let others =
            modules
            .filter { $0.name.lowercased() != "ownidcore" }
            .map { "\($0.name)/\($0.version)" }
            .joined(separator: " ")
        let deviceName = DeviceInfo.modelName
        let deviceDescriptor =
            (deviceName == rawMachineIdentifier) ? deviceName : "\(deviceName); \(rawMachineIdentifier)"
        let components: [String?] = [
            core ?? "OwnIDCore/0.0.0",
            "(iOS \(DeviceInfo.systemVersion); \(deviceDescriptor))",
            others,
            appBundleID,
        ]
        self.userAgent = components.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")

        if #available(iOS 16.0, *) {
            self.isSystemFidoCapable = true
        } else {
            self.isSystemFidoCapable = false
        }

        let ctx = LAContext()
        let isStrongBiometricEnabled = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let biometryType = ctx.biometryType

        self.isDeviceSecured = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        self.isFaceHardwarePresent = (biometryType == .faceID)
        self.isFingerprintHardwarePresent = (biometryType == .touchID)
        self.isStrongBiometricEnabled = isStrongBiometricEnabled
    }

    private struct DeviceInfo {

        internal static let systemVersion: String = {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }()

        internal static let machineIdentifier: String = {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            return machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
        }()

        internal static let modelName: String = {
            mapToDevice(identifier: machineIdentifier)
        }()

        // Keep this list scoped to identifiers that can realistically run the SDK's supported
        // deployment targets. Older devices fall back to the raw machine identifier.
        private static func mapToDevice(identifier: String) -> String {
            switch identifier {
            case "iPod9,1": return "iPod touch (7th generation)"
            case "iPhone8,1": return "iPhone 6s"
            case "iPhone8,2": return "iPhone 6s Plus"
            case "iPhone9,1", "iPhone9,3": return "iPhone 7"
            case "iPhone9,2", "iPhone9,4": return "iPhone 7 Plus"
            case "iPhone10,1", "iPhone10,4": return "iPhone 8"
            case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
            case "iPhone10,3", "iPhone10,6": return "iPhone X"
            case "iPhone11,2": return "iPhone XS"
            case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
            case "iPhone11,8": return "iPhone XR"
            case "iPhone12,1": return "iPhone 11"
            case "iPhone12,3": return "iPhone 11 Pro"
            case "iPhone12,5": return "iPhone 11 Pro Max"
            case "iPhone13,1": return "iPhone 12 mini"
            case "iPhone13,2": return "iPhone 12"
            case "iPhone13,3": return "iPhone 12 Pro"
            case "iPhone13,4": return "iPhone 12 Pro Max"
            case "iPhone14,4": return "iPhone 13 mini"
            case "iPhone14,5": return "iPhone 13"
            case "iPhone14,2": return "iPhone 13 Pro"
            case "iPhone14,3": return "iPhone 13 Pro Max"
            case "iPhone14,7": return "iPhone 14"
            case "iPhone14,8": return "iPhone 14 Plus"
            case "iPhone15,2": return "iPhone 14 Pro"
            case "iPhone15,3": return "iPhone 14 Pro Max"
            case "iPhone15,4": return "iPhone 15"
            case "iPhone15,5": return "iPhone 15 Plus"
            case "iPhone16,1": return "iPhone 15 Pro"
            case "iPhone16,2": return "iPhone 15 Pro Max"
            case "iPhone17,1": return "iPhone 16 Pro"
            case "iPhone17,2": return "iPhone 16 Pro Max"
            case "iPhone17,3": return "iPhone 16"
            case "iPhone17,4": return "iPhone 16 Plus"
            case "iPhone17,5": return "iPhone 16e"
            case "iPhone18,1": return "iPhone 17 Pro"
            case "iPhone18,2": return "iPhone 17 Pro Max"
            case "iPhone18,3": return "iPhone 17"
            case "iPhone18,4": return "iPhone Air"
            case "iPhone18,5": return "iPhone 17e"
            case "iPhone8,4": return "iPhone SE"
            case "iPhone12,8": return "iPhone SE (2nd generation)"
            case "iPhone14,6": return "iPhone SE (3rd generation)"
            case "iPad6,11", "iPad6,12": return "iPad (5th generation)"
            case "iPad7,5", "iPad7,6": return "iPad (6th generation)"
            case "iPad7,11", "iPad7,12": return "iPad (7th generation)"
            case "iPad11,6", "iPad11,7": return "iPad (8th generation)"
            case "iPad12,1", "iPad12,2": return "iPad (9th generation)"
            case "iPad13,18", "iPad13,19": return "iPad (10th generation)"
            case "iPad15,7", "iPad15,8": return "iPad (11th generation)"
            case "iPad5,3", "iPad5,4": return "iPad Air 2"
            case "iPad11,3", "iPad11,4": return "iPad Air (3rd generation)"
            case "iPad13,1", "iPad13,2": return "iPad Air (4th generation)"
            case "iPad13,16", "iPad13,17": return "iPad Air (5th generation)"
            case "iPad14,8", "iPad14,9": return "iPad Air (11-inch) (M2)"
            case "iPad14,10", "iPad14,11": return "iPad Air (13-inch) (M2)"
            case "iPad15,3", "iPad15,4": return "iPad Air (11-inch) (M3)"
            case "iPad15,5", "iPad15,6": return "iPad Air (13-inch) (M3)"
            case "iPad16,8", "iPad16,9": return "iPad Air (11-inch) (M4)"
            case "iPad16,10", "iPad16,11": return "iPad Air (13-inch) (M4)"
            case "iPad5,1", "iPad5,2": return "iPad mini 4"
            case "iPad11,1", "iPad11,2": return "iPad mini (5th generation)"
            case "iPad14,1", "iPad14,2": return "iPad mini (6th generation)"
            case "iPad16,1", "iPad16,2": return "iPad mini (A17 Pro)"
            case "iPad6,3", "iPad6,4": return "iPad Pro (9.7-inch)"
            case "iPad7,3", "iPad7,4": return "iPad Pro (10.5-inch)"
            case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPad Pro (11-inch) (1st generation)"
            case "iPad8,9", "iPad8,10": return "iPad Pro (11-inch) (2nd generation)"
            case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPad Pro (11-inch) (3rd generation)"
            case "iPad14,3", "iPad14,4": return "iPad Pro (11-inch) (4th generation)"
            case "iPad6,7", "iPad6,8": return "iPad Pro (12.9-inch) (1st generation)"
            case "iPad7,1", "iPad7,2": return "iPad Pro (12.9-inch) (2nd generation)"
            case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPad Pro (12.9-inch) (3rd generation)"
            case "iPad8,11", "iPad8,12": return "iPad Pro (12.9-inch) (4th generation)"
            case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPad Pro (12.9-inch) (5th generation)"
            case "iPad14,5", "iPad14,6": return "iPad Pro (12.9-inch) (6th generation)"
            case "iPad16,3", "iPad16,4": return "iPad Pro (11-inch) (M4)"
            case "iPad16,5", "iPad16,6": return "iPad Pro (13-inch) (M4)"
            case "iPad17,1", "iPad17,2": return "iPad Pro (11-inch) (M5)"
            case "iPad17,3", "iPad17,4": return "iPad Pro (13-inch) (M5)"
            case "i386", "x86_64", "arm64": return simulatorName(identifier: identifier)
            default: return identifier
            }
        }

        private static func simulatorName(identifier: String) -> String {
            if let simulatorName = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return mapToDevice(identifier: simulatorName) + "; simulator"
            } else {
                return "Simulator \(identifier)"
            }
        }
    }
}
