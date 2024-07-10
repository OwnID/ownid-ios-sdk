import Gigya
import OwnIDGigyaSDK

class ProfileCollectionViewModel: ObservableObject {
    @Published var name = ""
    @Published var password = ""
    @Published var errorMessage: String?
    
    private let loginId: String
    private let coordinator: AppCoordinator
    
    init(coordinator: AppCoordinator, loginId: String) {
        self.coordinator = coordinator
        self.loginId = loginId
    }
    
    func register() {
        let nameValue = "{ \"firstName\": \"\(name)\" }"
        let paramsDict = ["profile": nameValue]
        let params = OwnID.GigyaSDK.Registration.Parameters(parameters: paramsDict)
        
        Gigya.sharedInstance().register(email: loginId, password: password, params: params.parameters) { [weak self] result in
            switch result {
            case .success:
                self?.fetchProfile()
            case .failure:
                self?.errorMessage = "Registration error"
            }
        }
    }
    
    private func fetchProfile() {
        Task.init {
            if let profile = try? await Gigya.sharedInstance().getAccount(true).profile {
                let email = profile.email ?? ""
                let name = profile.firstName ?? ""
                let model = AccountModel(name: name, email: email)
                await MainActor.run {
                    coordinator.showLoggedIn(model: model)
                }
            } else {
                errorMessage = "Cannot find logged in profile"
            }
        }
    }
}
