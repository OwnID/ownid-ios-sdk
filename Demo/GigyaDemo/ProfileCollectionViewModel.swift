import Foundation
import Gigya
import OwnIDGigyaSDK

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
    
    init(coordinator: AppCoordinator, loginId: String) {
        self.coordinator = coordinator
        self.loginId = loginId
    }
    
    func register() {
        let paramsDict = ["profile": ["firstName": name]]
        let params = OwnID.GigyaSDK.Registration.Parameters(parameters: paramsDict)
        state = .loading
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
    
    func fetchProfile() {
        Task.init {
            if let profile = try? await Gigya.sharedInstance().getAccount(true).profile {
                let email = profile.email ?? ""
                let name = profile.firstName ?? ""
                let model = AccountModel(name: name, email: email)
                await MainActor.run {
                    state = .initial
                    coordinator.showLoggedIn(model: model)
                }
            } else {
                state = .initial
                errorMessage = "Cannot find logged in profile"
            }
        }
    }
}
