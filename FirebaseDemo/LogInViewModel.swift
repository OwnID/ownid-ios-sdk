import Combine
import OwnIDCoreSDK

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FirebaseSDK.loginViewModel()
    
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn:
                        fatalError("Show account here")
                        
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
