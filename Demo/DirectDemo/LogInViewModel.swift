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
        let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginIdPublisher: $loginId.eraseToAnyPublisher())
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
                    case .response(let loginId, let payload, let authMethod, let authToken):
                        self.loginId = loginId
                        
                        AuthSystem.login(ownIdData: payload.data, email: loginId)
                            .sink { completionRegister in
                                if case .failure(let error) = completionRegister {
                                    self.errorMessage = error.localizedDescription
                                }
                            } receiveValue: { result in
                                self.fetchProfile(previousResult: result.operationResult)
                            }
                            .store(in: &bag)
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let ownIDSDKError):
                    state = .initial
                    print(ownIDSDKError.localizedDescription)
                    errorMessage = ownIDSDKError.localizedDescription
                }
            }
            .store(in: &bag)
    }
    
    func logIn() {
        state = .loading
        AuthSystem.login(ownIdData: nil, password: password, email: loginId)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.state = .initial
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { result in
                self.state = .initial
                self.fetchProfile(previousResult: result.operationResult)
            }
            .store(in: &bag)
    }
    
    func appleLogin() {
        state = .loading
        OwnID.CoreSDK.startSocialLogin(type: .apple)
            .sink { [weak self] result in
                self?.handleSocialResult(result: result)
            }
            .store(in: &bag)
    }
    
    func googleLogin() {
        state = .loading
        OwnID.CoreSDK.startSocialLogin(type: .google)
            .sink { [weak self] result in
                self?.handleSocialResult(result: result)
            }
            .store(in: &bag)
    }
    
    private func handleSocialResult(result: Result<(String, String?), OwnID.CoreSDK.Error>) {
        switch result {
        case .success((_, let sessionPayload)):
            do {
                let data = Data((sessionPayload ?? "").utf8)
                let dataJson = try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
                let token = dataJson["token"] ?? ""
                fetchProfile(previousResult: token)
            } catch {
                state = .initial
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            state = .initial
            errorMessage = error.localizedDescription
        }
    }
    
    private func fetchProfile(previousResult: OperationResult) {
        AuthSystem.fetchUserData(previousResult: previousResult)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.errorMessage = error.localizedDescription
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
