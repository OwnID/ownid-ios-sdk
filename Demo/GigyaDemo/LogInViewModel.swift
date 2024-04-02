import Combine
import OwnIDCoreSDK
import Gigya

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        let ownIDViewModel = OwnID.GigyaSDK.loginViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.integrationEventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn:
                        Task.init {
                            if let profile = try? await Gigya.sharedInstance().getAccount(true).profile {
                                let email = profile.email ?? ""
                                let name = profile.firstName ?? ""
                                let model = AccountModel(name: name, email: email)
                                await MainActor.run {
                                    loggedInModel = model
                                }
                            } else {
                                errorMessage = "Cannot find logged in profile"
                            }
                        }
                        
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let error):
                    switch error {
                    case .integrationError(let gigyaError):
                        if let error = gigyaError as? NetworkError {
                            switch error {
                            case .gigyaError(let model):
                                //handling the error
                                print(model.errorMessage ?? "")
                            default: break
                            }
                        }

                    default:
                        break
                    }
                    print(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
            .store(in: &bag)
    }
}
