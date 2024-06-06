import Foundation
import OwnIDGigyaSDK
import Combine
import Gigya

extension RegisterViewModel {
    enum State {
        case initial
        case loading
    }
}

final class RegisterViewModel: ObservableObject {
    @Published private(set) var state = State.initial
    @Published var firstName = ""
    @Published var loginId = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    // MARK: OwnID
    @Published var isOwnIDEnabled = false
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    
    init() {
        let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: $loginId.eraseToAnyPublisher())
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
                        if let usersEmailFromWebApp, !usersEmailFromWebApp.isEmpty, loginId.isEmpty {
                            loginId = usersEmailFromWebApp
                        }
                        state = .initial
                        isOwnIDEnabled = true
                        
                    case .userRegisteredAndLoggedIn:
                        fetchProfile()
                        
                    case .loading:
                        print("Loading state")
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let ownIDSDKError):
                    print(ownIDSDKError.localizedDescription)
                    errorMessage = ownIDSDKError.localizedDescription
                    state = .initial
                    switch ownIDSDKError {
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
                }
            }
            .store(in: &bag)
    }
    
    func register() {
        state = .loading
        let nameValue = "{ \"firstName\": \"\(firstName)\" }"
        let paramsDict = ["profile": nameValue]
        let params = OwnID.GigyaSDK.Registration.Parameters(parameters: paramsDict)
        
        if isOwnIDEnabled {
            ownIDViewModel.register(registerParameters: params)
        } else {
            Gigya.sharedInstance().register(email: loginId, password: password, params: params.parameters) { [weak self] result in
                switch result {
                case .success:
                    self?.fetchProfile()
                    
                case .failure(_):
                    self?.state = .initial
                    self?.errorMessage = "Registration error"
                }
            }
        }
    }
    
    func fetchProfile() {
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
    }
    
    func reset() {
        state = .initial
        firstName = ""
        loginId = ""
        password = ""
        isOwnIDEnabled = false
        errorMessage = ""
    }
}
