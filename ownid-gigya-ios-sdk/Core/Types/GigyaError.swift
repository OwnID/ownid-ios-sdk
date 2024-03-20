import OwnIDCoreSDK
import Foundation
import Gigya

public extension OwnID.GigyaSDK {
    enum Error: PluginError {
        case gigyaSDKError(error: NetworkError, dataDictionary: [String: Any]?)
        case badIdTokenFormat
        case UIDIsMissing
        case idTokenNotFound
        case emailIsNotValid
        case passwordIsNotValid
        case mainSDKCancelled
        case cannotInitSession
        case cannotParseRegistrationMetadataParameter
        case cannotParseSession
    }
}

extension OwnID.GigyaSDK.Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .gigyaSDKError(let error, _):
            switch error {
            case .gigyaError(let data):
                return "[\(data.errorCode)] \(data.errorMessage ?? "")" 
            case .providerError(let data):
                return data
            case .networkError(let error):
                return error.localizedDescription
            case .jsonParsingError(let error):
                return error.localizedDescription
            default:
                return error.localizedDescription
            }
        case .badIdTokenFormat:
            return "Wrong id token format"
        case .emailIsNotValid:
            return "Email is not valid"
        case .passwordIsNotValid:
            return "Password is not valid"
        case .mainSDKCancelled:
            return "Cancelled"
        case .UIDIsMissing:
            return "UID is missing in account"
        case .idTokenNotFound:
            return "ID token is missing"
        case .cannotInitSession:
            return "Cannot create session"
        case .cannotParseRegistrationMetadataParameter:
            return "Registration parameters passed are invalid"
        case .cannotParseSession:
            return "Parsing error"
        }
    }
}
