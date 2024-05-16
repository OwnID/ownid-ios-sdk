import Foundation

final class AppCoordinator: ObservableObject {
    @Published private(set) var appState = AppState.loggedOut(.initial)

    public func showLoggedIn() {
        appState = .loggedIn
    }
    
    public func showLogInView() {
        appState = .loggedOut(.logIn)
    }
    
    public func showRegisterView() {
        appState = .loggedOut(.register)
    }
}
