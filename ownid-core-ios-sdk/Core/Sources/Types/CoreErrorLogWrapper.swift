import Foundation

public extension OwnID.CoreSDK {
    struct CoreErrorLogWrapper: Swift.Error {
        public init(error: OwnID.CoreSDK.Error, isOnUI: Bool = false, flowFinished: Bool = true) {
            self.error = error
            self.isOnUI = isOnUI
            self.flowFinished = flowFinished
        }
        
        public let error: OwnID.CoreSDK.Error
        public let isOnUI: Bool
        public let flowFinished: Bool
    }
}

public extension OwnID.CoreSDK.CoreErrorLogWrapper {
    @discardableResult
    static func coreLog<T>(error: OwnID.CoreSDK.Error,
                           function: String = #function,
                           file: String = #file,
                           isOnUI: Bool = false,
                           flowFinished: Bool = true,
                           type: T.Type = T.self) -> OwnID.CoreSDK.CoreErrorLogWrapper {
        let errorWrapper = OwnID.CoreSDK.CoreErrorLogWrapper(error: error, isOnUI: isOnUI, flowFinished: flowFinished)
        
        switch error {
        case .userError(let errorModel):
            if errorModel.code == .unknown {
                OwnID.CoreSDK.logger.log(level: .error,
                                         function: function,
                                         file: file,
                                         message: errorWrapper.errorMessage,
                                         type)
            }
        default:
            OwnID.CoreSDK.logger.log(level: .error,
                                     function: function,
                                     file: file,
                                     message: errorWrapper.errorMessage,
                                     type)
        }
        
        return errorWrapper
    }
    
    var errorMessage: String {
        switch error {
        case .userError(let errorModel):
            errorModel.message
        default:
            error.localizedDescription
        }
    }
    
    var errorCode: String? {
        switch error {
        case .userError(let errorModel):
            switch errorModel.code {
            case .unknown:
                return nil
            default:
                return errorModel.code.rawValue
            }
        default:
            return nil
        }
    }
}
