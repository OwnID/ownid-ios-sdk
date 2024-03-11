import Foundation
import OwnIDGigyaSDK
import Combine
import Gigya

final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    // MARK: OwnID
    @Published var isOwnIDEnabled = false
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    
    init() {
        let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.integrationEventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case let .readyToRegister(usersEmailFromWebApp, _):
                        if let usersEmailFromWebApp, !usersEmailFromWebApp.isEmpty, email.isEmpty {
                            email = usersEmailFromWebApp
                        }
                        isOwnIDEnabled = true
                        
                    case .userRegisteredAndLoggedIn:
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
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let ownIDSDKError):
                    print(ownIDSDKError.localizedDescription)
                    errorMessage = ownIDSDKError.localizedDescription
                    switch ownIDSDKError {
                    case .integrationError(let gigyaPluginError):
                        if let error = gigyaPluginError as? OwnID.GigyaSDK.IntegrationError {
                            switch error {
                            case .gigyaSDKError(let networkError, let dataDictionary):
                                switch networkError {
                                case .gigyaError(let model):
                                    //handling the data
                                    print(dataDictionary ?? "")
                                    print(model.errorMessage ?? "")
                                default: break
                                }
                            }
                        }

                    default:
                        break
                    }
                }
            }
            .store(in: &bag)
    }
    
    func register() {
        if isOwnIDEnabled {
            let nameValue = "{ \"firstName\": \"\(firstName)\" }"
            let paramsDict = ["profile": nameValue]
            let params = OwnID.GigyaSDK.Registration.Parameters(parameters: paramsDict)
            ownIDViewModel.register(registerParameters: params)
        } else {
            // ignoring register with default login & password
        }
    }
}
