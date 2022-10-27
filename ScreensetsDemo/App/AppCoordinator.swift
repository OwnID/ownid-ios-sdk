import SwiftUI
import DemoComponents
import OwnIDCoreSDK

extension AppCoordinator {
    enum State {
        case loggedIn
        case loggedOut
    }
}

final class AppCoordinator: ObservableObject, CoordinatorLogoutAction {
    @Published private(set) var state = State.loggedOut
    @Published var logInViewModel: LogInViewModel!
    @Published var loggedInViewModel: LoggedInView.ViewModel?
    
    init() {
        logInViewModel = LogInViewModel(coordinator: self)
    }
    
    func showLoggedIn() {
        loggedInViewModel = LoggedInView.ViewModel(coordinator: self,
                                                   loggenInObject: GigyaLoggedIn(),
                                                   previousResult: VoidOperationResult())
        state = .loggedIn
    }
    
    func showLoggedOut() {
        state = .loggedOut
        loggedInViewModel = .none
    }
}
