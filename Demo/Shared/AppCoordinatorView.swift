import SwiftUI

public struct AppCoordinatorView: View {
    @EnvironmentObject var coordinator: AppCoordinator    
    
    public var body: some View {
        switch coordinator.appState {
        case .loggedIn(let model):
            AccountView(model: model)
        case .loggedOut:
            WelcomeView()
        }
    }
}
