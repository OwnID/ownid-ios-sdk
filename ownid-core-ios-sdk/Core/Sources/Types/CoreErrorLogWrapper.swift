import Foundation

public extension OwnID.CoreSDK {
    struct ErrorWrapper {
        public init(error: OwnID.CoreSDK.Error,
                    isOnUI: Bool = false,
                    flowFinished: Bool = true,
                    function: String = #function,
                    file: String = #file,
                    type: Any.Type) {
            self.error = error
            self.isOnUI = isOnUI
            self.flowFinished = flowFinished
            self.function = function
            self.file = file
            self.type = type
        }
        
        let error: OwnID.CoreSDK.Error
        let isOnUI: Bool
        let flowFinished: Bool
        let function: String
        let file: String
        let type: Any.Type
        
        
        public func log(customErrorMessage: String? = nil) {
            let message: String
            if let customErrorMessage {
                message = customErrorMessage
            } else {
                message = error.errorMessage
            }
            
            switch error {
            case .userError(let errorModel):
                if errorModel.code == .unknown {
                    OwnID.CoreSDK.logger.log(level: .error,
                                             function: function,
                                             file: file,
                                             message: message,
                                             type: type)
                }
            default:
                OwnID.CoreSDK.logger.log(level: .error,
                                         function: function,
                                         file: file,
                                         message: message,
                                         type: type)
            }
        }
    }
}
