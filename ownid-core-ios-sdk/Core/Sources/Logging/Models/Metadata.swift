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
    
    struct Metadata: Encodable {
        var correlationId: String?
        var stackTrace: String?
        var sessionRequestSequenceNumber: String?
        var widgetPosition: WidgetPositionType?
        var widgetType: WidgetType?
        var authType: String?
        var hasLoginId: Bool?
        var validLoginIdFormat: Bool?
        let applicationName = OwnID.CoreSDK.shared.store.value.configuration?.displayName
        var isUserVerifyingPlatformAuthenticatorAvailable = ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 16,
                                                                                                                          minorVersion: 0,
                                                                                                                          patchVersion: 0))
        
        static func metadata(authType: String? = nil,
                             actionType: AnalyticActionType,
                             hasLoginId: Bool? = nil,
                             validLoginIdFormat: Bool? = nil) -> Metadata {
            var metadata = Metadata()
            metadata.correlationId = LoggerConstants.instanceID.uuidString
            if let hasLoginId {
                metadata.hasLoginId = hasLoginId
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
