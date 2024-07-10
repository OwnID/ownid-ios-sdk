import Combine
import OwnIDGigyaSDK
import Gigya

final class WelcomeViewModel: ObservableObject {
    @Published var notFoundLoginId: String?
    @Published var errorMessage: String?
    
    private let coordinator: AppCoordinator
    
    private var bag = Set<AnyCancellable>()
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
    
    func startFlow() {
        OwnID.GigyaSDK.start()
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
                        if let session = GigyaSession(sessionToken: session.sessionToken,
                                                      secret: session.sessionSecret,
                                                      expiration: session.expiration) {
                            Gigya.sharedInstance().setSession(session)
                            self?.fetchProfile()
                        } else {
                            self?.errorMessage = ""
                        }
                    }
                }
            }
            .store(in: &bag)
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
