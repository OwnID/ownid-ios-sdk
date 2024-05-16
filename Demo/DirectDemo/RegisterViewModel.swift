import Foundation
import OwnIDCoreSDK
import Combine

final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var loginId = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var ownIdData: String?
    
    private var bag = Set<AnyCancellable>()
    
    // MARK: OwnID
    @Published var isOwnIDEnabled = false
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    
    init() {
        let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(loginIdPublisher: $loginId.eraseToAnyPublisher())
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
                        self.loginId = loginId
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
        AuthSystem.register(ownIdData: isOwnIDEnabled ? ownIdData : nil,
                            password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                            email: loginId,
                            name: firstName)
        .sink { completionRegister in
            if case .failure(let error) = completionRegister {
                self.errorMessage = error.localizedDescription
            }
        } receiveValue: { result in
            self.fetchProfile(previousResult: result.operationResult)
        }
        .store(in: &bag)
    }
    
    private func fetchProfile(previousResult: OperationResult) {
        AuthSystem.fetchUserData(previousResult: previousResult)
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
