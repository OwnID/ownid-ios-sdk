import Foundation

extension Bundle {
    static func appName() -> String {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return ProcessInfo.processInfo.environment["XCInjectBundle"] ?? ""
        }

        guard let dictionary = Bundle.main.infoDictionary else {
            return ""
        }

        if let version: String = dictionary["CFBundleName"] as? String {
            return version
        } else {
            return ""
        }
    }
}
