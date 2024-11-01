import Foundation
import OwnIDCoreSDK

enum FlowResult: Equatable {
    case profileCollect(params: [String: Any]?)
    case loggedIn(account: AccountModel?)
    case error(error: OwnID.CoreSDK.Error)
    case close
    
    static func == (lhs: FlowResult, rhs: FlowResult) -> Bool {
        switch (lhs, rhs) {
        case (.loggedIn(let account1), .loggedIn(let account2)):
            return account1 == account2
        case (.error(let error1), .error(let error2)):
            return error1.localizedDescription == error2.localizedDescription
        case (.close, .close):
            return true
        default:
            return false
        }
    }
}
