import Foundation
import OwnIDGigyaSDK
import Combine
import AccountView
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
        let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance(), emailPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribeToEmailChanges()
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
        eventsPublisher
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
                    case .plugin(let gigyaPluginError):
                        if let gigyaSDKError = gigyaPluginError as? OwnID.GigyaSDK.Error<GigyaAccount> {
                            switch gigyaSDKError {
                            case .login(let loginError):
                                switch loginError.interruption {
                                case .pendingVerification:
                                    errorMessage = ownIDSDKError.localizedDescription + ", pending verification"
                                    print("pendingVerification")

                                default:
                                    break
                                }
                            default:
                                break
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

private extension RegisterViewModel {
    func subscribeToEmailChanges() {
        $email
            .removeDuplicates()
            .debounce(for: .seconds(0.77), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                guard let self = self else { return }
                self.ownIDViewModel.shouldShowTooltip = self.ownIDViewModel.shouldShowTooltipEmailProcessingClosure(value)
            })
            .store(in: &bag)
    }
}
