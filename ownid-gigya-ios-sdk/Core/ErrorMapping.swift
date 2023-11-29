import Gigya
import OwnIDCoreSDK

extension OwnID.GigyaSDK {
    final class ErrorMapper<AccountType: GigyaAccountProtocol> {
        static func mapRegistrationError(error: LoginApiError<AccountType>, context: String?, loginId: String?, authType: String?) {
            switch error.error {
            case .gigyaError(let data):
                let gigyaError = data.errorCode
                if allowedActionsErrorCodes().contains(gigyaError) {
                    OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .registered,
                                                                       category: .registration,
                                                                       context: context,
                                                                       loginId: loginId,
                                                                       authType: authType,
                                                                       source: String(describing: Self.self)))
                }
                
            default:
                break
            }
        }
        
        static func mapLoginError(errorCode: Int, context: String?, loginId: String?, authType: String?) {
            if allowedActionsErrorCodes().contains(errorCode) {
                OwnID.CoreSDK.eventService.sendMetric(.trackMetric(action: .loggedIn,
                                                                   category: .login,
                                                                   context: context,
                                                                   loginId: loginId,
                                                                   authType: authType,
                                                                   source: String(describing: Self.self)))
            }
        }
        
        private static func allowedActionsErrorCodes() -> [Int] { [206001, 206002, 206006, 403102, 403101] }
    }
}
