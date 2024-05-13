import Foundation

extension OwnID.CoreSDK.EnrollManager {
    enum ResultRequestBodyType: String, Encodable {
        case publicKey = "public-key"
    }
    
    struct ResultRequestBodyResponse: Encodable {
        let clientDataJSON: String
        let attestationObject: String
        
        init(clientDataJSON: String, attestationObject: String) {
            self.clientDataJSON = clientDataJSON
            self.attestationObject = attestationObject
        }
    }
    
    struct ResultRequestBody: Encodable {
        let id: String
        let type: ResultRequestBodyType
        let response: ResultRequestBodyResponse
        
        init(id: String, type: ResultRequestBodyType, response: ResultRequestBodyResponse) {
            self.id = id
            self.type = type
            self.response = response
        }
    }
}
