import OwnIDCoreSDK
import Foundation
import Gigya

public extension OwnID.GigyaSDK {
    enum ErrorMessage {
        static let cannotInitSession = "Cannot create session"
        static let cannotParseRegistrationMetadataParameter = "Registration parameters passed are invalid"
        static let cannotParseSession = "Parsing error"
    }
    
    static func gigyaErrorMessage(_ error: NetworkError) -> String {
        switch error {
        case .gigyaError(let data):
            data.errorMessage ?? error.localizedDescription
        case .providerError(let data):
            data
        default:
            error.localizedDescription
            
        }
    }
}
