import Foundation
import AuthenticationServices

public extension OwnID.CoreSDK {
    enum FlowType {
        case idCollect
        case fidoRegister
        case fidoLogin
        case otp(flowType: String)
        case webApp
        case enroll
        
        var source: String? {
            switch self {
            case .idCollect:
                return "LoginId Completion"
            case .otp(let flowType):
                return flowType
            case .webApp:
                return "Web App"
            default:
                return nil
            }
        }
    }
}

extension OwnID.CoreSDK {
    enum ErrorMessage {
        static let SDKConfigurationError = "No OwnID instance available. Check if OwnID instance created"
        static let redirectParameterFromURLCancelledOpeningSDK = "In redirection URL \"redirect=false\" has been found and opening of SDK cancelled. This is most likely due to app has been opened in screensets mode."
        static let notValidRedirectionURLOrNotMatchingFromConfiguration = "Error returning value from browser"
        static let noServerConfig = "No server configuration available"
        static let noLocalConfig = "No local configuration available"
        static let payloadMissing = "Payload missing"
        static let emptyResponseData = "Response data is empty"
        static let requestError = "Error while performing action"
        static let webFrameError = "Requests from subframes are not supported"
        static let fidoUnavailable = "FIDO unavailable"
        static let enrollmentSkipped = "Credential enrollment was skipped"
        
        static func dataIsMissingError(dataInfo: String? = nil) -> String {
            if let dataInfo {
                return "Data is missing: \(dataInfo)"
            }
            return "Data is missing"
        }
        
        static func webSchemeURLError(urlString: String) -> String {
            return "WebAuthn not permitted for current URL: \(urlString)"
        }
        
        static func encodingError(description: String) -> String {
            return "Encoding Failed \(description)"
        }
        
        static func decodingError(description: String) -> String {
            return "Decoding Failed \(description)"
        }
    }
}

public extension OwnID.CoreSDK {
    enum Error: Swift.Error {
        case flowCancelled(flow: FlowType)
        case integrationError(underlying: Swift.Error)
        case userError(errorModel: UserErrorModel)
    }
    
    struct UserErrorModel: Equatable {
        public let code: ErrorTypeCode
        public let message: String
        public let userMessage: String
    
        public init(code: String?, message: String?, userMessage: String?) {
            self.code = ErrorTypeCode(rawValue: code ?? "") ?? .unknown
            self.message = message ?? ""
            self.userMessage = userMessage ?? OwnID.CoreSDK.TranslationsSDK.TranslationKey.stepsError.localized()
        }
        
        public init(message: String) {
            self.message = message
            self.code = .unknown
            self.userMessage = OwnID.CoreSDK.TranslationsSDK.TranslationKey.stepsError.localized()
        }
        
        var isGeneralError: Bool {
            code == .unknown || code == .userAlreadyExists || code == .flowIsFinished
        }
    }
    
    enum ErrorTypeCode: String {
        case accountNotFound = "AccountNotFound"
        case requiresBiometricInput = "RequiresBiometricInput"
        case accountIsBlocked = "AccountIsBlocked"
        case userAlreadyExists = "UserAlreadyExists"
        case userNotFound = "UserNotFound"
        case wrongCodeLimitReached = "WrongCodeLimitReached"
        case flowIsFinished = "FlowIsFinished"
        case invalidCode = "WrongCodeEntered"
        case sendCodeLimitReached = "SendCodeLimitReached"
        case flowCanceled = "FlowCanceled"
        case unknown
    }
}

extension OwnID.CoreSDK.Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .flowCancelled(let flow):
            return "User canceled OwnID flow \(flow)"

        case .integrationError(let error):
            return error.localizedDescription
            
        case .userError(let model):
            return model.userMessage
        }
    }
}

extension OwnID.CoreSDK.Error: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .flowCancelled,
                .integrationError,
                .userError:
            return errorDescription ?? ""
        }
    }
}

extension OwnID.CoreSDK.Error {
    var metricErrorCode: String? {
        switch self {
        case .userError(let errorModel):
            switch errorModel.code {
            case .unknown:
                return nil
            default:
                return errorModel.code.rawValue
            }
        case .flowCancelled:
            return OwnID.CoreSDK.ErrorTypeCode.flowCanceled.rawValue
        default:
            return nil
        }
    }
    
    var errorMessage: String {
        switch self {
        case .userError(let errorModel):
            errorModel.message
        case .integrationError(let error):
            error.localizedDescription
        default:
            localizedDescription
        }
    }
}
