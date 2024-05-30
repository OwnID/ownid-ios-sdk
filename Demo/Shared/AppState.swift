import Foundation

enum AppState {
    case loggedIn(model: AccountModel)
    case loggedOut
}
