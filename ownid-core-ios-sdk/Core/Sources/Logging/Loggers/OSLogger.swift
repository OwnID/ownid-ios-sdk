import Foundation
import OSLog

extension OwnID.CoreSDK {
    final class OSLogger: LoggerProtocol {
        private var logger = os.Logger(subsystem: "OwnID.\(String(describing: OwnID.CoreSDK.self))", category: "OSLogger")
        
        func log(priority: Int, codeInitiator: String, message: String, errorMessage: String?) {
            switch priority {
            case 0:
                logger.debug("\(message)")
            case 1:
                logger.info("\(message)")
            case 2:
                logger.error("\(message)")
            case 3:
                logger.fault("\(message)")
            default:
                logger.debug("\(message)")
            }
        }
    }
}
