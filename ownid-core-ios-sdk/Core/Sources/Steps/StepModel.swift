import Foundation

extension OwnID.CoreSDK.CoreViewModel {
    struct Step: Decodable {
        enum StepType: String, Decodable {
            case starting
            case fido2Authorize
            case linkWithCode
            case loginIDAuthorization
            case verifyLoginID
            case showQr
            case success
        }
        
        let type: StepType
        private(set) var startingData: StartingStepData?
        private(set) var fidoData: FidoStepData?
        private(set) var otpData: OTPStepData?
        private(set) var webAppData: WebAppStepData?
        
        enum CodingKeys: CodingKey {
            case type
            case data
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(StepType.self, forKey: .type)
            
            switch type {
            case .starting:
                self.startingData = try container.decodeIfPresent(StartingStepData.self, forKey: .data)
            case .fido2Authorize:
                self.fidoData = try container.decodeIfPresent(FidoStepData.self, forKey: .data)
            case .linkWithCode, .loginIDAuthorization, .verifyLoginID:
                self.otpData = try container.decodeIfPresent(OTPStepData.self, forKey: .data)
            case .showQr:
                self.webAppData = try container.decodeIfPresent(WebAppStepData.self, forKey: .data)
            case .success:
                break
            }
        }
    }
    
    struct StartingStepData: Decodable {
        let url: String
    }
    
    enum Operation: String, Decodable {
        case login, register
    }
    
    struct FidoStepData: Decodable {
        let rpId: String
        let rpName: String
        let url: String?
        let userDisplayName: String
        let userName: String
        let operation: Operation?
        let credsIds: [String]
        
        enum CodingKeys: CodingKey {
            case relyingPartyId
            case relyingPartyName
            case url
            case userDisplayName
            case userName
            case operation
            case credId
            case credsIds
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.rpId = try container.decode(String.self, forKey: .relyingPartyId)
            self.rpName = try container.decode(String.self, forKey: .relyingPartyName)
            self.url = try container.decodeIfPresent(String.self, forKey: .url)
            self.userDisplayName = try container.decode(String.self, forKey: .userDisplayName)
            self.userName = try container.decode(String.self, forKey: .userName)
            self.operation = try container.decodeIfPresent(Operation.self, forKey: .operation)
            
            let credId = try container.decodeIfPresent(String.self, forKey: .credId)
            let credsIds = try container.decodeIfPresent([String].self, forKey: .credsIds)
            
            if let credsIds, !credsIds.isEmpty {
                self.credsIds = credsIds
            } else if let credId {
                self.credsIds = [credId]
            } else {
                self.credsIds = []
            }
        }
    }
    
    struct OTPStepData: Decodable {
        let url: String
        let restartUrl: String
        let resendUrl: String
        let verificationType: OwnID.CoreSDK.Verification.VerificationType
        let otpLength: Int?
    }
    
    struct WebAppStepData: Decodable {
        let url: String
    }
    
    struct ErrorData: Decodable {
        let errorCode: String?
        let message: String?
        let userMessage: String?
        let flowFinished: Bool?
    }
}
