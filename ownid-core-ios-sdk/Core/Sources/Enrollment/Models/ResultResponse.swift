import Foundation

extension OwnID.CoreSDK.EnrollManager {
    enum ResultResponseStatus: String, Decodable {
        case ok, failed
    }
    
    struct ResultResponse: Decodable {
        let status: ResultResponseStatus
        let errorMessage: String?
    }
}
