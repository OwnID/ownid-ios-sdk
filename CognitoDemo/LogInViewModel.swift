import Combine
import OwnIDCoreSDK

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    
    @Published var email = ""
    @Published var errorMessage = ""
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        let ownIDViewModel = OwnID.AmplifySDK.loginViewModel(emailPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn(let result, _):
                        let tokensContainer = result as? OwnID.AmplifySDK.DataContainerOperationResult
                        print(tokensContainer?.dataContainer.idToken)
                        
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let error):
                    print(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
            .store(in: &bag)
    }
}
