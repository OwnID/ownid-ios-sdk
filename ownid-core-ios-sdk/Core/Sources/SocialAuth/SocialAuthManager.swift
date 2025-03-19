import Combine

extension OwnID.CoreSDK {
    final class SocialAuthManager {
        var store: Store<State, Action>
        
        private let resultPublisher = PassthroughSubject<(String, String?), OwnID.CoreSDK.Error>()
        private var bag = Set<AnyCancellable>()
        
        private var eventPublisher: OwnID.SocialEventPublisher {
            return resultPublisher
                .map { event -> Result<(String, String?), OwnID.CoreSDK.Error> in
                    return .success(event)
                }
                .catch { error -> AnyPublisher<Result<(String, String?), OwnID.CoreSDK.Error>, Never> in
                    return Just(.failure(error)).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
        
        init(type: SocialProviderType, provider: SocialProvider? = nil) {
            let store = Store(initialValue: State(type: type, provider: provider), reducer: Self.reducer)
            self.store = store
            
            setupEventPublisher()
        }
        
        func start() -> OwnID.SocialEventPublisher {
            store.send(.checkProvider)
            
            return eventPublisher
        }
        
        private func setupEventPublisher() {
            store
                .actionsPublisher
                .sink { [weak self] action in
                    switch action {
                    case .finish(let accessToken, let sessionPayload):
                        self?.resultPublisher.send((accessToken, sessionPayload))
                        self?.resultPublisher.send(completion: .finished)
                    case .error(let wrapper):
                        self?.resultPublisher.send(completion: .failure(wrapper.error))
                    default:
                        break
                    }
                }
                .store(in: &bag)
        }
    }
}
