import Foundation

protocol NamespaceHandler {
    var name: OwnID.CoreSDK.Namespace { set get }
    var actions: [String] { set get }
    
    func invoke(bridgeContext: OwnID.CoreSDK.WebBridgeContext,
                action: String,
                params: String,
                metadata: OwnID.CoreSDK.JSMetadata?,
                completion: @escaping (_ result: String) -> Void)
}
