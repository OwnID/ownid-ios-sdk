import Foundation

public extension OwnID.CoreSDK {
    enum WidgetPositionType: String, Encodable {
        case start = "start"
        case end = "end"
    }
    
    enum WidgetType: String, Encodable {
        case faceid = "button-faceid"
        case client = "client-button"
        case auth = "ownid-auth-button"
    }
    
    struct DeviceSecurityStatus: Encodable {
        let isDeviceSecured: Bool
        let isFaceHardwarePresent: Bool
        let isFingerprintHardwarePresent: Bool
        let isStrongBiometricEnabled: Bool
    }
    
    struct Metadata: Encodable {
        var correlationId: String?
        var stackTrace: String?
        var sessionRequestSequenceNumber: String?
        var widgetPosition: WidgetPositionType?
        var widgetType: WidgetType?
        var authType: String?
        var hasLoginId: Bool?
        var validLoginIdFormat: Bool?
        var loginType: LoginType?
        var webViewOrigin: String?
        var widgetId: String?
        let applicationName = OwnID.CoreSDK.shared.store.value.configuration?.displayName
        var deviceSecurityStatus: DeviceSecurityStatus?
        var isUserVerifyingPlatformAuthenticatorAvailable = ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 16,
                                                                                                                          minorVersion: 0,
                                                                                                                          patchVersion: 0))
        
        static func metadata(authType: String? = nil,
                             actionType: AnalyticActionType,
                             hasLoginId: Bool? = nil,
                             loginType: LoginType? = nil,
                             validLoginIdFormat: Bool? = nil,
                             webViewOrigin: String? = nil,
                             widgetId: String? = nil) -> Metadata {
            var metadata = Metadata()
            metadata.correlationId = LoggerConstants.instanceID.uuidString
            metadata.loginType = loginType
            if let hasLoginId {
                metadata.hasLoginId = hasLoginId
            }
            if let loginType {
                metadata.loginType = loginType
            }
            if let authType {
                metadata.authType = authType
            }
            if actionType.isPositionAndTypeAdding {
                let current = OwnID.CoreSDK.shared.currentMetricInformation
                metadata.widgetPosition = current.widgetPositionType
                metadata.widgetType = current.widgetType
            }
            if let validLoginIdFormat {
                metadata.validLoginIdFormat = validLoginIdFormat
            }
            if let webViewOrigin {
                metadata.webViewOrigin = webViewOrigin
            }
            if let widgetId {
                metadata.widgetId = widgetId
            }
            
            let isAppleIDAvailable = FileManager.default.ubiquityIdentityToken != nil
            let isStrongBiometricEnabled = isPasscodeAvailable && (isFaceIDAvailable || isTouchIDAvailable) && isAppleIDAvailable
            metadata.deviceSecurityStatus = DeviceSecurityStatus(isDeviceSecured: isPasscodeAvailable,
                                                                 isFaceHardwarePresent: isFaceIDAvailable,
                                                                 isFingerprintHardwarePresent: isTouchIDAvailable,
                                                                 isStrongBiometricEnabled: isStrongBiometricEnabled)
            return metadata
        }
    }
}

extension OwnID.CoreSDK.Metadata: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        correlationId: \(correlationId ?? "")
        """
    }
}
