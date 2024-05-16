import Foundation
import OwnIDCoreSDK
import Combine

final class RegisterViewModel: ObservableObject {
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
        let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: Registration(),
                                                                   loginPerformer: Login(),
                                                                   loginIdPublisher: $loginId.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.integrationEventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case let .readyToRegister(usersEmailFromWebApp, _):
                        if let usersEmailFromWebApp, !usersEmailFromWebApp.isEmpty, loginId.isEmpty {
                            loginId = usersEmailFromWebApp
                        }
                        isOwnIDEnabled = true
                        
                    case .userRegisteredAndLoggedIn(let registrationResult, _):
                        fetchProfile(previousResult: registrationResult)
                    case .loading:
                        print("Loading state")
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let ownIDSDKError):
                    print(ownIDSDKError.localizedDescription)
                    errorMessage = ownIDSDKError.localizedDescription
                    switch ownIDSDKError {
                    case .integrationError(let integrationError):
                        if let error = integrationError as? IntegrationError {
                            switch error {
                            case .registrationDataError(let message):
                                print(message)
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
            ownIDViewModel.register(registerParameters: RegistrationParameters(firstName: firstName))
        } else {
            CustomAuthSystem.register(ownIdData: nil, password: password, email: loginId, name: firstName)
                .sink { completionRegister in
                    if case .failure(let error) = completionRegister {
                        self.errorMessage = error.localizedDescription
                    }
                } receiveValue: { result in
                    self.fetchProfile(previousResult: result.operationResult)
                }
                .store(in: &bag)
        }
    }
    
    private func fetchProfile(previousResult: OperationResult) {
        CustomAuthSystem.fetchUserData(previousResult: previousResult)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { model in
                self.loggedInModel = AccountModel(name: model.name, email: model.email)
            }
            .store(in: &bag)
    }
}
