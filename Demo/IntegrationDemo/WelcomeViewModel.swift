import Combine
import OwnIDCoreSDK

final class WelcomeViewModel: ObservableObject {
    @Published var notFoundLoginId: String?
    @Published var errorMessage: String?
    
    private let coordinator: AppCoordinator
    private var sessionAdapter = MySessionAdapter()
    
    private var bag = Set<AnyCancellable>()
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
    
    func startFlow() {
        OwnID.CoreSDK.start(adapter: sessionAdapter)
            .sink { [weak self] result in
                switch result {
                case .success(let event):
                    switch event {
                    case .close:
                        break
                    case .error(let error):
                        self?.errorMessage = error.localizedDescription
                    case .accountNotFound(let loginId, _, _):
                        self?.notFoundLoginId = loginId
                    case .login(let session, _, _):
                        self?.fetchProfile(previousResult: session.token)
                    }
                }
            }
            .store(in: &bag)
    }
    
    private func fetchProfile(previousResult: OperationResult) {
        CustomAuthSystem.fetchUserData(previousResult: previousResult)
            .sink { [weak self] completionRegister in
                if case .failure(let error) = completionRegister {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] model in
                self?.coordinator.showLoggedIn(model: AccountModel(name: model.name, email: model.email))
            }
            .store(in: &bag)
    }
}

struct MySessionAdapter: SessionAdapter {
    func transform(session: String) throws -> LoginResponse {
        let data = session.data(using: .utf8) ?? Data()
        let response = try JSONDecoder().decode(LoginResponse.self, from: data)
        return response
    }
}
