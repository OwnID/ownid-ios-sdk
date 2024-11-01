import Foundation
import Combine
import OwnIDCoreSDK

extension ProfileCollectionViewModel {
    enum State {
        case initial
        case loading
    }
}

class ProfileCollectionViewModel: ObservableObject {
    @Published private(set) var state = State.initial
    @Published var name = ""
    @Published var password = ""
    @Published var errorMessage = ""
    
    private let loginId: String
    private let coordinator: AppCoordinator
    private var bag = Set<AnyCancellable>()
    
    init(coordinator: AppCoordinator, loginId: String) {
        self.coordinator = coordinator
        self.loginId = loginId
    }
    
    func register() {
        state = .loading
        CustomAuthSystem.register(ownIdData: nil, password: password, email: loginId, name: name)
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
                    self.state = .initial
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { model in
                self.state = .initial
                self.coordinator.showLoggedIn(model: AccountModel(name: model.name, email: model.email))
            }
            .store(in: &bag)
    }
}
