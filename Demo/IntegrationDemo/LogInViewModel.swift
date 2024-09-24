import Combine
import OwnIDCoreSDK

extension LogInViewModel {
    enum State {
        case initial
        case loading
    }
}

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    
    @Published private(set) var state = State.initial
    @Published var loginId = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: Login(),
                                                                loginIdPublisher: $loginId.eraseToAnyPublisher())
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
                    case .loggedIn(let loginResult, _):
                        fetchProfile(previousResult: loginResult)
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let ownIDSDKError):
                    state = .initial
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
    
    func logIn() {
        state = .loading
        CustomAuthSystem.login(ownIdData: nil, password: password, email: loginId)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.state = .initial
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { result in
                self.fetchProfile(previousResult: result.operationResult)
            }
            .store(in: &bag)
    }
    
    private func fetchProfile(previousResult: OperationResult) {
        CustomAuthSystem.fetchUserData(previousResult: previousResult)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.errorMessage = error.localizedDescription
                    self.state = .initial
                }
            } receiveValue: { model in
                self.loggedInModel = AccountModel(name: model.name, email: model.email)
            }
            .store(in: &bag)
    }
    
    func reset() {
        state = .initial
        loginId = ""
        password = ""
        errorMessage = ""
    }

}
