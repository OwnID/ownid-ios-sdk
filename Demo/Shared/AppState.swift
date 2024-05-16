import Foundation

enum AppState: Equatable {
    case loggedIn
    case loggedOut(LoggedOutState)
    
    var loggedOutState: LoggedOutState {
        switch self {
        case .loggedIn:
            return .logIn
            
        case .loggedOut(let loggedOut):
            switch loggedOut {
            case .logIn:
                return .logIn
                
            case .conflictingAccounts(let loginId):
                return .conflictingAccounts(loginId: loginId)
                
            case .register:
                return .register
                
            case .initial:
                return .initial
            }
        }
    }
    
    enum LoggedOutState: Equatable {
        case initial
        case logIn
        case register
        case conflictingAccounts(loginId: String?)
    }
}
