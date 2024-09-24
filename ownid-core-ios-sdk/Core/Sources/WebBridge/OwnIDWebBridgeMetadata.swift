import Foundation

extension OwnID.CoreSDK {
    final class WebBridgeMetadata: NamespaceHandler {
        struct JSCorrelation: Encodable {
            let correlationId: String
        }
        
        var name = Namespace.METADATA
        var actions: [String] = ["get"]
        
        func invoke(bridgeContext: OwnID.CoreSDK.WebBridgeContext, 
                    action: String,
                    params: String,
                    metadata: OwnID.CoreSDK.JSMetadata?,
                    completion: @escaping (String) -> Void) {
            switch action {
            case "get":
                let JSCorrelation = JSCorrelation(correlationId: OwnID.CoreSDK.LoggerConstants.instanceID.uuidString)
                guard let jsonData = try? JSONEncoder().encode(JSCorrelation),
                      let result = String(data: jsonData, encoding: String.Encoding.utf8) else {
                    completion("")
                    return
                }
                completion(result)
            default:
                break
            }
        }
    }
}
