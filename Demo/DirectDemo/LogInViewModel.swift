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
        let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginIdPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.flowEventPublisher)
    }
    
    func subscribe(to flowEventPublisher: OwnID.LoginFlowPublisher) {
        flowEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .response(let loginId, let payload, let authType):
                        email = loginId
                        
                        AuthSystem.login(ownIdData: payload.data, email: loginId)
                            .sink { completionRegister in
                                if case .failure(let error) = completionRegister {
                                    self.errorMessage = error.localizedDescription
                                }
                            } receiveValue: { result in
                                self.fetchUserData(result: result.operationResult)
                            }
                            .store(in: &bag)
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let ownIDSDKError):
                    print(ownIDSDKError.localizedDescription)
                    errorMessage = ownIDSDKError.localizedDescription
                }
            }
            .store(in: &bag)
    }
    
    private func fetchUserData(result: OperationResult) {
        AuthSystem.fetchUserData(previousResult: result)
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
