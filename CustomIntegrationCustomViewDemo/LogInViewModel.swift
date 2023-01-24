import Combine
import OwnIDCoreSDK
import AccountView

final class CustomLoginPerformer: LoginPerformer {
    func login(payload: OwnID.CoreSDK.Payload,
               email: String) -> OwnID.LoginResultPublisher {
        LoginRequest.login(ownIdData: payload.dataContainer, email: email)
    }
}

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    let customButtonPublisher = PassthroughSubject<Void, Never>()
    private var loginToken: String!
    
    private var bag = Set<AnyCancellable>()
    
    init() {
        let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: CustomLoginPerformer(),
                                                                sdkConfigurationName: AppDelegate.clientName,
                                                                emailPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.eventPublisher)
        ownIDViewModel.subscribe(to: customButtonPublisher.eraseToAnyPublisher())
    }
    
    func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn(let previousResultToken, _):
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
