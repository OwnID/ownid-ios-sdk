import OwnIDCoreSDK
import Foundation
import Gigya

public extension OwnID.GigyaSDK {
    enum ErrorMessage {
        static let cannotInitSession = "Cannot create session"
        static let cannotParseRegistrationMetadataParameter = "Registration parameters passed are invalid"
        static let cannotParseSession = "Parsing error"
        static let accountNeedsVerification = "Needs account verification"
    }
    
    enum IntegrationError: Swift.Error {
        case gigyaSDKError(gigyaError: NetworkError, dataDictionary: [String: Any]?)
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

extension OwnID.GigyaSDK.IntegrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .gigyaSDKError(let gigyaError, _):
            switch gigyaError {
            case .gigyaError(let data):
                return data.errorMessage
            case .providerError(let data):
                return data
            case .networkError(let error):
                return error.localizedDescription
            case .jsonParsingError(let error):
                return error.localizedDescription
            default:
                return gigyaError.localizedDescription
            }
        }
    }
}
