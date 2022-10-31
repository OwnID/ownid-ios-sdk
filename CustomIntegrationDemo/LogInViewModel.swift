import Combine
import OwnIDCoreSDK
import AccountView

struct LoginResponse: Decodable {
    let token: String
}

final class CustomLoginPerformer: LoginPerformer {
    func login(payload: OwnID.CoreSDK.Payload,
               email: String) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        LogInViewModel.login(ownIdData: payload.dataContainer, email: email)
    }
}

final class LogInViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: CustomLoginPerformer(),
                                                            sdkConfigurationName: DemoApp.clientName,
                                                            webLanguages: .init(rawValue: Locale.preferredLanguages))
    
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
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
                    case .loggedIn:
                        if let email = Auth.auth().currentUser?.email {
                            let name = Auth.auth().currentUser?.displayName ?? ""
                            let model = AccountModel(name: name, email: email)
                            loggedInModel = model
                        } else {
                            errorMessage = "Cannot find logged in email"
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
    
    static func login(ownIdData: Any?,
                      email: String) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        if let ownIdData = ownIdData as? [String: String], let token = ownIdData["token"] {
            return Just(token)
                .setFailureType(to: OwnID.CoreSDK.Error.self)
                .eraseToAnyPublisher()
        }
        let payloadDict = ["email": email, "password": password]
        return Just(payloadDict)
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
            .tryMap { try JSONSerialization.data(withJSONObject: $0) }
            .map { payloadData -> URLRequest in
                var request = URLRequest(url: URL(string: "https://node-mongo.custom.demo.dev.ownid.com/api/auth/login")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = payloadData
                return request
            }
            .flatMap {
                URLSession.shared.dataTaskPublisher(for: $0)
                    .mapError { OwnID.CoreSDK.Error.statusRequestNetworkFailed(underlying: $0) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
            .map { $0.data }
            .decode(type: LoginResponse.self, decoder: JSONDecoder())
            .map { $0.token }
            .receive(on: DispatchQueue.main)
            .mapError { OwnID.CoreSDK.Error.plugin(error: CustomIntegrationDemoError.loginRequestFailed(underlying: $0)) }
            .eraseToAnyPublisher()
    }
}
