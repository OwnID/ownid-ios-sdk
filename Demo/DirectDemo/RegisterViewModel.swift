import Foundation
import OwnIDCoreSDK
import Combine

final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var ownIdData: String?
    
    private var bag = Set<AnyCancellable>()
    
    // MARK: OwnID
    @Published var isOwnIDEnabled = false
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    
    init() {
        let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(loginIdPublisher: $email.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.flowEventPublisher)
    }
    
    func subscribe(to flowEventPublisher: OwnID.RegistrationFlowPublisher) {
        flowEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .response(let loginId, let payload, let authType):
                        isOwnIDEnabled = true
                        email = loginId
                        ownIdData = payload.data
                    case .loading:
                        print("Loading state")
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let ownIDSDKError):
                    print(ownIDSDKError.localizedDescription)
                    errorMessage = ownIDSDKError.localizedDescription
                }
            }
            .store(in: &bag)
    }
    
    func register() {
        if isOwnIDEnabled {
            AuthSystem.register(ownIdData: ownIdData, 
                                password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                                email: email,
                                name: firstName)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { result in
                self.fetchUserData(result: result.operationResult)
            }
            .store(in: &bag)
        } else {
            // ignoring register with default login & password
        }
    }
    
    private func fetchUserData(result: OperationResult) {
        AuthSystem.fetchUserData(previousResult: result)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { model in
                self.loggedInModel = AccountModel(name: model.name, email: model.email)
            }
            .store(in: &bag)
    }
}
