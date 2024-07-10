import OwnIDCoreSDK
import Combine

class ProfileCollectionViewModel: ObservableObject {
    @Published var name = ""
    @Published var password = ""
    @Published var errorMessage: String?
    
    private let loginId: String
    private let coordinator: AppCoordinator
    
    private var bag = Set<AnyCancellable>()
    
    init(coordinator: AppCoordinator, loginId: String) {
        self.coordinator = coordinator
        self.loginId = loginId
    }
    
    func register() {
        AuthSystem.register(ownIdData: nil,
                            password: password,
                            email: loginId,
                            name: name)
        .sink { [weak self] completionRegister in
            if case .failure(let error) = completionRegister {
                self?.errorMessage = error.localizedDescription
            }
        } receiveValue: { [weak self] result in
            self?.fetchProfile(previousResult: result.operationResult)
        }
        .store(in: &bag)
    }
    
    private func fetchProfile(previousResult: OperationResult) {
        AuthSystem.fetchUserData(previousResult: previousResult)
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
