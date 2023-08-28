import Combine
import OwnIDCoreSDK
import AccountView
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
        let ownIDViewModel = OwnID.GigyaSDK.loginViewModel(instance: Gigya.sharedInstance())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
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
                    case .plugin(let gigyaPluginError):
                        if let error = gigyaPluginError as? OwnID.GigyaSDK.Error {
                            switch error {
                            case .gigyaSDKError(let networkError, let dataDictionary):
                                switch networkError {
                                case .gigyaError(let model):
                                    //handling the data
                                    print(dataDictionary)
                                    print(model.errorMessage)
                                default: break
                                }
                            default:
                                break
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
