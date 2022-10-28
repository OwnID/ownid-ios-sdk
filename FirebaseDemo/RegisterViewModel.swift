import Foundation
import OwnIDFirebaseSDK
import Combine

final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var email = ""
    @Published var password = ""
    
    private var bag = Set<AnyCancellable>()
    
    // MARK: OwnID
    @Published var isOwnIDEnabled = false
    let ownIDViewModel = OwnID.FirebaseSDK.registrationViewModel()
    
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
                        
                    case .userRegisteredAndLoggedIn:
                        fatalError("Show account here")
                        
                    case .loading:
                        print("Loading state")
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let error):
                    print(error.localizedDescription)
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
