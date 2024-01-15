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
        let message: String
        switch error {
        case .userError(let errorModel):
            message = errorModel.message
        default:
            message = error.localizedDescription
        }
        
        OwnID.CoreSDK.logger.log(level: .error,
                                 function: function,
                                 file: file,
                                 message: message,
                                 type)
        return OwnID.CoreSDK.CoreErrorLogWrapper(error: error, isOnUI: isOnUI, flowFinished: flowFinished)
    }
}
