import Foundation
import Combine
import AccountView
import OwnIDCoreSDK

final class CustomRegistrationParameters: RegisterParameters {
    internal init(firstName: String) {
        self.firstName = firstName
    }
    
    let firstName: String
}

final class CustomRegistration: RegistrationPerformer {
    func register(configuration: OwnID.FlowsSDK.RegistrationConfiguration, parameters: RegisterParameters) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        let ownIdData = configuration.payload.dataContainer
        return RegisterViewModel.register(ownIdData: ownIdData as? String,
                                          password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                                          email: configuration.email.rawValue,
                                          name: (parameters as? CustomRegistrationParameters)?.firstName ?? "no name in CustomRegistration class")
    }
}

final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    // MARK: OwnID
    @Published var isOwnIDEnabled = false
    let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: CustomRegistration(),
                                                               loginPerformer: CustomLoginPerformer(),
                                                               sdkConfigurationName: AppDelegate.clientName,
                                                               webLanguages: .init(rawValue: Locale.preferredLanguages))
    
    init() {
        subscribeToEmailChanges()
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case let .readyToRegister(usersEmailFromWebApp):
                        if let usersEmailFromWebApp, !usersEmailFromWebApp.isEmpty, email.isEmpty {
                            email = usersEmailFromWebApp
                        }
                        isOwnIDEnabled = true
                        
                    case .userRegisteredAndLoggedIn(let previousResultToken):
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
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let error):
                    print(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
            .store(in: &bag)
    }
    
    func register() {
        if isOwnIDEnabled {
            ownIDViewModel.register(with: email)
        } else {
            // ignoring register with default login & password
        }
    }
}

private extension RegisterViewModel {
    func subscribeToEmailChanges() {
        $email
            .removeDuplicates()
            .debounce(for: .seconds(0.77), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                guard let self = self else { return }
                self.ownIDViewModel.shouldShowTooltip = self.ownIDViewModel.shouldShowTooltipEmailProcessingClosure(value)
            })
            .store(in: &bag)
    }
}

extension RegisterViewModel {
    static func register(ownIdData: String?,
                         password: String,
                         email: String,
                         name: String) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        var payloadDict = ["email": email, "password": password, "name": name]
        if let ownIdData {
            payloadDict["ownIdData"] = ownIdData
        }
        return urlSessionRequest(for: payloadDict)
            .tryMap { response -> Void in
                if !response.data.isEmpty {
                    throw OwnID.CoreSDK.Error.payloadMissing(underlying: String(data: response.data, encoding: .utf8))
                }
            }
            .eraseToAnyPublisher()
            .flatMap { _ -> AnyPublisher<OperationResult, Error> in
                LogInViewModel.login(ownIdData: ownIdData, email: email).mapError { $0 as Error }.eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .mapError { error in
                return OwnID.CoreSDK.Error.flowCancelled
            }
            .eraseToAnyPublisher()
    }
    
    private static func urlSessionRequest(for payloadDict: [String: Any]) -> AnyPublisher<URLSession.DataTaskPublisher.Output, OwnID.CoreSDK.Error> {
        return Just(payloadDict)
            .setFailureType(to: OwnID.CoreSDK.Error.self)
            .eraseToAnyPublisher()
            .tryMap { try JSONSerialization.data(withJSONObject: $0) }
            .mapError { OwnID.CoreSDK.Error.initRequestBodyEncodeFailed(underlying: $0) }
            .map { payloadData -> URLRequest in
                var request = URLRequest(url: URL(string: "https://node-mongo.custom.demo.dev.ownid.com/api/auth/register")!)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = payloadData
                return request
            }
            .eraseToAnyPublisher()
            .flatMap { request -> AnyPublisher<URLSession.DataTaskPublisher.Output, OwnID.CoreSDK.Error> in
                URLSession.shared.dataTaskPublisher(for: request)
                    .mapError { OwnID.CoreSDK.Error.statusRequestNetworkFailed(underlying: $0) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}
