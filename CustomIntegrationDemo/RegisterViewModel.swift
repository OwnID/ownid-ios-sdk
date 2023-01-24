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
    func register(configuration: OwnID.FlowsSDK.RegistrationConfiguration, parameters: RegisterParameters) -> OwnID.RegistrationResultPublisher {
        let ownIdData = configuration.payload.dataContainer
        return RegisterRequest.register(ownIdData: ownIdData as? String,
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
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    
    init() {
        let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: CustomRegistration(),
                                                                   loginPerformer: CustomLoginPerformer(),
                                                                   sdkConfigurationName: AppDelegate.clientName,
                                                                   emailPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribeToEmailChanges()
        subscribe(to: ownIDViewModel.eventPublisher)
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case let .readyToRegister(usersEmailFromWebApp, _):
                        if let usersEmailFromWebApp, !usersEmailFromWebApp.isEmpty, email.isEmpty {
                            email = usersEmailFromWebApp
                        }
                        isOwnIDEnabled = true
                        
                    case .userRegisteredAndLoggedIn(let previousResultToken, _):
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
            ownIDViewModel.register(registerParameters: CustomRegistrationParameters(firstName: firstName))
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
