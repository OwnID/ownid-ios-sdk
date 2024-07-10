import OwnIDCoreSDK
import Combine
import Gigya

final class AccountViewModel: ObservableObject {
    private var bag = Set<AnyCancellable>()
    
    func logOut() {
        Gigya.sharedInstance().logout()
    }
    
    func enroll(force: Bool) {
        OwnID.CoreSDK.enrollCredential(loginIdPublisher: loginIdPublisher(),
                                       authTokenPublisher: authTokenPublisher(),
                                       force: force)
            .receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .success:
                    print("success")
                    
                case .failure(let error):
                    switch error {
                    case .userError(let errorModel):
                        print(errorModel.message)
                        print(errorModel.userMessage)
                    case .flowCancelled(let flow):
                        switch flow {
                        case .enroll:
                            print("cancel enroll")
                        case .fidoRegister:
                            print("cancel fido register")
                        default:
                            break
                        }
                    default:
                        break
                    }
                    break
                }
            }
            .store(in: &bag)
    }
}

private extension AccountViewModel {
    private func loginIdPublisher() -> AnyPublisher<String, Never> {
        Future<String, Never> { promise in
            Gigya.sharedInstance().getAccount(true) { result in
                switch result {
                case .success(let data):
                    promise(.success(data.profile?.email ?? ""))
                case .failure(let error):
                    print(error)
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func authTokenPublisher() -> AnyPublisher<String, Never> {
        Future<String, Never> { promise in
            Gigya.sharedInstance().send(api: "accounts.getJWT") { result in
                switch result {
                case .success(let data):
                    let authToken = data["id_token"]?.value as? String
                    promise(.success(authToken ?? ""))
                case .failure(let error):
                    print(error)
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
