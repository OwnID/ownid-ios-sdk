import Foundation
import OwnIDCoreSDK
import Combine

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
            $0.session {
                $0.create { [unowned self] loginId, session, authToken, authMethod in
                    let token = session["token"] as? String ?? ""
                    let result = await fetchProfile(previousResult: token)
                    return result
                }
            }
            $0.account {
                $0.register { [unowned self] loginId, profile, ownIdData, authToken in
                    do {
                        let registerResult = try await register(loginId: loginId, profile: profile, ownIdData: ownIdData)
                        let result = await fetchProfile(previousResult: registerResult)
                        return result
                    } catch {
                        return .fail(reason: error.localizedDescription)
                    }
                }
            }
        }
        
        OwnID.start {
            $0.providers {
                $0.auth {
                    $0.password {
                        $0.authenticate { [unowned self] loginId, password in
                            do {
                                let loginResult = try await login(loginId: loginId, password: password)
                                let result = await fetchProfile(previousResult: loginResult)
                                return result
                            } catch {
                                return .fail(reason: error.localizedDescription)
                            }
                        }
                    }
                }
            }
            $0.events {
                $0.onFinish { loginId, authMethod, authToken in
                    subject.send(.loggedIn(account: self.loggedInModel))
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
    
    private func fetchProfile(previousResult: OperationResult) async -> OwnID.AuthResult {
        await withCheckedContinuation { continuation in
            AuthSystem.fetchUserData(previousResult: previousResult)
                .sink { completion in
                    if case .failure(let error) = completion {
                        self.errorMessage = error.localizedDescription
                        continuation.resume(returning: .fail(reason: error.localizedDescription))
                    }
                } receiveValue: { model in
                    self.loggedInModel = AccountModel(name: model.name, email: model.email)
                    continuation.resume(returning: .loggedIn)
                }
                .store(in: &bag)
        }
    }
    
    private func register(loginId: String, profile: [String: Any], ownIdData: [String: Any]?) async throws -> OperationResult {
        return try await withCheckedThrowingContinuation { continuation in
            let firstName = profile["firstName"] as? String ?? ""
            
            let jsonData = try? JSONSerialization.data(withJSONObject: ownIdData ?? [:])
            let ownIdDataString = String(data: jsonData ?? Data(), encoding: .utf8)
            
            AuthSystem.register(ownIdData: ownIdDataString,
                                password: OwnID.FlowsSDK.Password.generatePassword().passwordString,
                                email: loginId,
                                name: firstName)
            .sink { completionRegister in
                if case .failure(let error) = completionRegister {
                    self.errorMessage = error.localizedDescription
                    continuation.resume(throwing: error)
                }
            } receiveValue: { result in
                continuation.resume(returning: result.operationResult)
            }
            .store(in: &bag)
        }
    }
    
    private func login(loginId: String, password: String) async throws -> OperationResult {
        return try await withCheckedThrowingContinuation { continuation in
            AuthSystem.login(ownIdData: nil, password: password, email: loginId)
                .sink { completionRegister in
                    if case .failure(let error) = completionRegister {
                        self.errorMessage = error.localizedDescription
                        continuation.resume(throwing: error)
                    }
                } receiveValue: { result in
                    continuation.resume(returning: result.operationResult)
                }
                .store(in: &bag)
        }
    }
}
