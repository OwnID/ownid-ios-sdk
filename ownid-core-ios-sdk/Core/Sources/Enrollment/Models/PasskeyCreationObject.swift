import Foundation

extension OwnID.CoreSDK.EnrollManager {
    enum AttestationType: String, Decodable {
        case none, direct, indirect, enterprise
    }
    
    struct RelyingParty: Decodable {
        let id: String
        let name: String
    }
    
    struct PasskeyCreationUser: Decodable {
        let id: String
        let name: String
        let displayName: String
    }
    
    struct PubKeyCredParam: Decodable {
        let type: String
        let alg: Int
    }
    
    struct ExcludeCredential: Decodable {
        let id: String
        let type: String
        let trasports: [String]?
    }
    
    enum AuthenticatorAttachment: String, Decodable {
        case platform
        case crossPlatform = "cross-platform"
    }
    
    enum UserVerification: String, Decodable {
        case preferred, required, discouraged
    }
    
    enum ResidentKey: String, Decodable {
        case preferred, required, discouraged
    }
    
    struct AuthenticatorSelection: Decodable {
        let authenticatorAttachment: AuthenticatorAttachment?
        let requireResidentKey: Bool
        let userVerification: UserVerification
        let residentKey: ResidentKey
    }
    
    struct FIDOCreateModel: Decodable {
        let challenge: String
        let rp: RelyingParty
        let user: PasskeyCreationUser
        let pubKeyCredParams: [PubKeyCredParam]
        let attestation: AttestationType?
        let excludeCredentials: [ExcludeCredential]?
        let authenticatorSelection: AuthenticatorSelection
    }
}
