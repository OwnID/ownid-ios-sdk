import Foundation
import OwnIDFirebaseSDK
import Combine
import AccountView
import FirebaseAuth

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
        let ownIDViewModel = OwnID.FirebaseSDK.registrationViewModel(emailPublisher: $email.eraseToAnyPublisher())
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
                        
                    case .userRegisteredAndLoggedIn:
                        if let email = Auth.auth().currentUser?.email {
                            let name = Auth.auth().currentUser?.displayName ?? ""
                            let model = AccountModel(name: name, email: email)
                            loggedInModel = model
                        } else {
                            errorMessage = "Cannot find logged in email"
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
