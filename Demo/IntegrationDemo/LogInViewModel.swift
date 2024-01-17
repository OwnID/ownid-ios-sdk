import Combine
import OwnIDCoreSDK

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: Login(),
                                                                sdkConfigurationName: IntegrationDemoApp.clientName,
                                                                loginIdPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn(let loginResult, _):
                        CustomAuthSystem.fetchUserData(previousResult: loginResult)
                            .sink { completionRegister in
                                if case .failure(let error) = completionRegister {
                                    self.errorMessage = error.localizedDescription
                                }
                            } receiveValue: { model in
                                self.loggedInModel = AccountModel(name: model.name, email: model.email)
                            }
                            .store(in: &bag)
                    case .loading:
                        print("Loading state")
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
}
