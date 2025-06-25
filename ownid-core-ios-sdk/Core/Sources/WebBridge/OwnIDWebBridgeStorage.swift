import Foundation

extension OwnID.CoreSDK {
    final class WebBridgeStorage: NamespaceHandler {
        struct JSStorage: Codable {
            let loginId: String
            let authMethod: String?
        }
        
        var name = Namespace.STORAGE
        var actions: [String] = ["setLastUser", "getLastUser"]
        
        func invoke(bridgeContext: OwnID.CoreSDK.WebBridgeContext, 
                    action: String,
                    params: String,
                    metadata: OwnID.CoreSDK.JSMetadata?,
                    completion: @escaping (String) -> Void) {
            switch action {
            case "setLastUser":
                do {
                    let jsonData = params.data(using: .utf8) ?? Data()
                    let loginIdSaver = try JSONDecoder().decode(JSStorage.self, from: jsonData)
                    
                    let authType = AuthType(rawValue: loginIdSaver.authMethod ?? "")
                    LoginIdSaver.save(loginId: loginIdSaver.loginId, authMethod: AuthMethod.authMethod(from: authType))
                    
                    completion("{}")
                } catch {
                    let errorModel = OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription)
                    ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self).log()
                    
                    completion(handleErrorResult(errorMessage: error.localizedDescription))
                }
            case "getLastUser":
                if let loginId = DefaultsLoginIdSaver.loginId(), !loginId.isEmpty {
                    let authMethod = LoginIdDataSaver.loginIdData(from: loginId)?.authMethod
                    
                    let storage = JSStorage(loginId: loginId, authMethod: authMethod?.rawValue)
                    
                    do {
                        let jsonData = try JSONEncoder().encode(storage)
                        let result = String(data: jsonData, encoding: .utf8)
                        completion(result ?? "{}")
                    } catch {
                        let errorModel = OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription)
                        ErrorWrapper(error: .userError(errorModel: errorModel), type: Self.self).log()
                        
                        completion(handleErrorResult(errorMessage: error.localizedDescription))
                    }
                } else {
                    completion("{}")
                }
            default:
                break
            }
        }
        
        private func handleErrorResult(errorMessage: String) -> String {
            let error = JSError(error: OwnID.CoreSDK.JSErrorData(
                name: self.name.rawValue,
                type: String(describing: Self.self),
                message: errorMessage)
            )
            
            guard let jsonData = try? JSONEncoder().encode(error),
                  let errorString = String(data: jsonData, encoding: String.Encoding.utf8) else {
                return "{}"
            }
            return errorString
        }
    }
}
