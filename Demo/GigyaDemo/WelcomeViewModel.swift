import Foundation
import OwnIDGigyaSDK
import Combine
import Gigya

final class WelcomeViewModel: ObservableObject {
    private var errorMessage: String?
    private var loggedInModel: AccountModel?
    
    @Published var flowResult: FlowResult?
    
    private var bag = Set<AnyCancellable>()
    
    func startFlow() {
        start()
            .receive(on: DispatchQueue.main)
            .sink { result in
                self.flowResult = result
            }
            .store(in: &bag)
    }
    
    private func start() -> AnyPublisher<FlowResult, Never> {
        let subject = PassthroughSubject<FlowResult, Never>()
        
        OwnID.providers {
            OwnID.GigyaSDK.gigyaProviders($0)
        }
        
        OwnID.start {
            $0.events {
                $0.onFinish { loginId, authMethod, authToken in
                    let result = await self.fetchProfile()
                    subject.send(result)
                }
                $0.onError { error in
                    subject.send(.error(error: error))
                }
                $0.onClose {
                    subject.send(.close)
                }
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    private func fetchProfile() async -> FlowResult {
        do {
            let profile = try await Gigya.sharedInstance().getAccount(true).profile
            let email = profile?.email ?? ""
            let name = profile?.firstName ?? ""
            let model = AccountModel(name: name, email: email)
            return .loggedIn(account: model)
        } catch {
            return .error(error: .integrationError(underlying: error))
        }
    }
}
