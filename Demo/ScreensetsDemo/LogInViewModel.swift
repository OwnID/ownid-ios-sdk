import SwiftUI
import Combine
import Gigya

final class LogInViewModel: ObservableObject {
    private(set) var screensetResult = PassthroughSubject<GigyaPluginEvent<GigyaAccount>, Never>()
    
    @Published var errorMessage = ""
    @Published var loggedInModel: AccountModel?
    
    private var bag = Set<AnyCancellable>()
    
    internal init() {
        screensetResult
            .sink { [unowned self] result in
                
                switch result {
                case .onLogin:
                    Task.init {
                        if let profile = try? await Gigya.sharedInstance().getAccount(true).profile {
                            let email = profile.email ?? ""
                            let name = profile.firstName ?? ""
                            let model = AccountModel(name: name, email: email)
                            try await Task.sleep(until: .now + .seconds(1), clock: .continuous)
                            await MainActor.run {
                                loggedInModel = model
                            }
                        } else {
                            errorMessage = "Cannot find logged in profile"
                        }
                    }
                    
                case .error(let error):
                    var message = error["errorMessage"] as? String ?? ""
                    if let details = error["errorDetails"] as? String {
                        message.append(" Details: \(details)")
                    }
                    errorMessage = message
                    
                default:
                    print(result)
                }
                
            }
            .store(in: &bag)
    }
}
