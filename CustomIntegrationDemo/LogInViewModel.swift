import Combine
import OwnIDCoreSDK
import AccountView

final class CustomLoginPerformer: LoginPerformer {
    func login(payload: OwnID.CoreSDK.Payload,
               email: String) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        LoginRequest.login(ownIdData: payload.dataContainer, email: email)
    }
}

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: CustomLoginPerformer(),
                                                            sdkConfigurationName: AppDelegate.clientName,
                                                            webLanguages: .init(rawValue: Locale.preferredLanguages))
    
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    private var loginToken: String!
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn(let previousResultToken):
                        Task.init {
                            if let model = try? await ProfileLoader().loadProfile(previousResult: previousResultToken) {
                                await MainActor.run {
                                    loggedInModel = model
                                }
                            } else {
                                errorMessage = "Cannot find logged in model"
                            }
                        }
                        
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let error):
                    print(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
            .store(in: &bag)
    }
}
