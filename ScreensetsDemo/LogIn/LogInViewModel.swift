import SwiftUI
import Combine
import Gigya
import DemoComponents

extension LogInViewModel {
    enum State {
        case initial
        case loading
    }
}

final class LogInViewModel: ObservableObject {
    private(set) var screensetResult = PassthroughSubject<GigyaPluginEvent<OwnIDAccount>, Never>()
    
    @Published private(set) var state = State.initial
    
    private unowned let coordinator: AppCoordinator
    
    @Published var email = ""
    @Published var password = ""
    
    @Published var inlineError: String?
    
    private var bag = Set<AnyCancellable>()
    
    internal init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        screensetResult
            .sink { [unowned self] result in
                state = .initial
                
                switch result {
                case .onLogin:
                    redirectToLoggedIn()
                case .error(let error):
                    var message = error["errorMessage"] as? String ?? ""
                    if let details = error["errorDetails"] as? String {
                        message.append(" Details: \(details)")
                    }
                    handleError(error: message)
                    
                default:
                    print(result)
                }
                
            }
            .store(in: &bag)
    }
    
    func logIn() {
        state = .loading
    }
}

private extension LogInViewModel {
    
    func redirectToLoggedIn() {
        reset()
        coordinator.showLoggedIn()
    }
    
    func handleError(error: String) {
        state = .initial
        inlineError = error
    }
    
    func reset() {
        state = .initial
        inlineError = .none
        email = ""
        password = ""
    }
}
