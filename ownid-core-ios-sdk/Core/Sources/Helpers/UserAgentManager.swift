import Foundation
import UIKit.UIDevice

public extension OwnID.CoreSDK {
    /// Relates version and name of the client.
    /// Examples:
    /// name - "com.example.myapp", "DemoApplication"
    /// version - "0.0.5", "3.34.7"
    typealias SDKInformation = (name: String, verison: String)
    
    final class UserAgentManager {
        public static let shared = UserAgentManager()
        private init() { }
        
        private let modelName = UIDevice.modelName
        
        func registerUserFacingSDKName(_ userFacingSDK: SDKInformation, underlyingSDKs: [SDKInformation]) {
            var allUnderlyingSDKs: [SDKInformation] = [OwnID.CoreSDK.info()]
            allUnderlyingSDKs.append(contentsOf: underlyingSDKs)
            SDKUserAgent = userAgent(for: userFacingSDK, underlyingSDKs: allUnderlyingSDKs)
            version = version(for: userFacingSDK, underlyingSDKs: allUnderlyingSDKs)
            sdkName = sdkFullName(sdkName: userFacingSDK.name)
        }
        
        private var systemVersion: String { UIDevice.current.systemVersion }
        
        @Published public var sdkName = OwnID.CoreSDK.sdkName
        public lazy var SDKUserAgent = userAgent(for: (OwnID.CoreSDK.sdkName, OwnID.CoreSDK.version), underlyingSDKs: [])
        lazy var version: String = version(for: (OwnID.CoreSDK.sdkName, OwnID.CoreSDK.version), underlyingSDKs: [])
        
        private func version(for userFacingSDK: SDKInformation, underlyingSDKs: [SDKInformation]) -> String {
            let userFacingSDKName = sdkAgentName(sdkName: userFacingSDK.name, version: userFacingSDK.verison)
            let underlyingSDKsNames = underlyingSDKNames(underlyingSDKs: underlyingSDKs)
            return "\(userFacingSDKName) \(underlyingSDKsNames)"
        }
        
        private func userAgent(for userFacingSDK: SDKInformation, underlyingSDKs: [SDKInformation]) -> String {
            let userFacingSDKName = sdkAgentName(sdkName: userFacingSDK.name, version: userFacingSDK.verison)
            let underlyingSDKsNames = underlyingSDKNames(underlyingSDKs: underlyingSDKs)
            sdkName = sdkFullName(sdkName: OwnID.CoreSDK.sdkName)
            return "\(userFacingSDKName) (iOS; iOS \(systemVersion); \(modelName)) \(underlyingSDKsNames) \(Bundle.main.bundleIdentifier!)"
        }
        
        private func sdkFullName(sdkName: String) -> String {
            if !sdkName.hasPrefix("OwnID") {
                "OwnID\(sdkName)"
            } else {
                sdkName
            }
            
        }
        
        private func sdkAgentName(sdkName: String, version: String) -> String {
            "\(sdkFullName(sdkName: sdkName))/\(version)"
        }
        
        private func underlyingSDKNames(underlyingSDKs: [SDKInformation]) -> String {
            underlyingSDKs.reduce("") { partialResult, sdkInfo in
                let newUnderlying = sdkAgentName(sdkName: sdkInfo.name, version: sdkInfo.verison)
                if partialResult == "" {
                    return newUnderlying
                } else {
                    return partialResult +  " " + newUnderlying
                }
            }
        }
    }
}
