import Combine
import Foundation

extension OwnID.CoreSDK {
    final class EnrollManager {
        var store: Store<State, Action>
        
        private let resultPublisher = PassthroughSubject<Void, OwnID.CoreSDK.Error>()
        private var bag = Set<AnyCancellable>()
        
        private var eventPublisher: OwnID.EnrollEventPublisher {
            return resultPublisher
                .map { event -> Result<Void, OwnID.CoreSDK.Error> in
                    return .success(event)
                }
                .catch { error -> AnyPublisher<Result<Void, OwnID.CoreSDK.Error>, Never> in
                    return Just(.failure(error)).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
        
        init(supportedLanguages: OwnID.CoreSDK.Languages) {
            let store = Store(initialValue: State(supportedLanguages: supportedLanguages), reducer: Self.reducer)
            self.store = store
            
            let enrollViewStore = self.store.view(
                value: { _ in OwnID.UISDK.Enroll.ViewState() },
                action: { .enrollView($0) },
                action: { globalAction in
                    return nil
                },
                reducer: { OwnID.UISDK.Enroll.viewModelReducer(state: &$0, action: $1) }
            )
            
            let authManagerStore = self.store.view(value: { _ in AuthManager.State() },
                                                   action: { .authManager($0) })
            
            store.send(.addToState(enrollViewStore: enrollViewStore, authStore: authManagerStore))
            
            setupEventPublisher()
        }
        
        func enroll(loginIdPublisher: AnyPublisher<String, Never>,
                    authTokenPublisher: AnyPublisher<String, Never>,
                    displayNamePublisher: AnyPublisher<String, Never>,
                    force: Bool) -> OwnID.EnrollEventPublisher {
            store.send(.addPublishers(loginIdPublisher: loginIdPublisher,
                                      authTokenPublisher: authTokenPublisher,
                                      displayNamePublisher: displayNamePublisher,
                                      force: force))
            return eventPublisher
        }
        
        private func setupEventPublisher() {
            store
                .actionsPublisher
                .sink { [weak self] action in
                    switch action {
                    case .fidoUnavailable(let error):
                        self?.resultPublisher.send(completion: .failure(error))
                    case .skip(let error):
                        if let error {
                            self?.resultPublisher.send(completion: .failure(error))
                        }
                    case .error(let wrapper):
                        self?.resultPublisher.send(completion: .failure(wrapper.error))
                    case .cancelled(let flow):
                        let error = OwnID.CoreSDK.Error.flowCancelled(flow: flow)
                        self?.resultPublisher.send(completion: .failure(error))
                    case .finished:
                        self?.resultPublisher.send()
                    default:
                        break
                    }
                }
                .store(in: &bag)
        }
    }
}
