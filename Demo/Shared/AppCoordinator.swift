import Foundation

final class AppCoordinator: ObservableObject {
    @Published private(set) var appState = AppState.loggedOut
    
    public func showLoggedOut() {
        appState = .loggedOut
    }
    
    public func showLoggedIn(model: AccountModel) {
        appState = .loggedIn(model: model)
    }
}
