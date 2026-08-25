import Combine
import Foundation

extension OwnID.CoreSDK {
    final class EnrollManager {
        var store: Store<State, Action>
        
        private let resultPublisher = PassthroughSubject<Void, OwnID.CoreSDK.Error>()
        private var bag = Set<AnyCancellable>()
        private var lifecycle = Lifecycle.inactive
        private var pendingEnrollment: PendingEnrollment?
        private var inputBridges = [InputBridge]()

        final class InputBridge {
            private let lock = NSLock()
            private let subject = CurrentValueSubject<String?, Never>(nil)
            private var upstream: AnyCancellable?
            private var isConnected = false
            private var isCancelled = false
            private var isUpstreamCompleted = false

            var publisher: AnyPublisher<String, Never> {
                subject.compactMap { $0 }.eraseToAnyPublisher()
            }

            func connect(to publisher: AnyPublisher<String, Never>) {
                lock.lock()
                guard !isConnected, !isCancelled else {
                    lock.unlock()
                    return
                }
                isConnected = true
                lock.unlock()

                let cancellable = publisher.sink(receiveCompletion: { [weak self] _ in
                    guard let self else { return }
                    lock.lock()
                    isUpstreamCompleted = true
                    upstream = nil
                    lock.unlock()
                }, receiveValue: { [weak self] value in
                    guard let self else { return }
                    lock.lock()
                    let shouldSend = !isCancelled
                    lock.unlock()
                    if shouldSend {
                        subject.send(value)
                    }
                })

                lock.lock()
                if isCancelled || isUpstreamCompleted {
                    lock.unlock()
                    cancellable.cancel()
                } else {
                    upstream = cancellable
                    lock.unlock()
                }
            }

            func cancel() {
                lock.lock()
                guard !isCancelled else {
                    lock.unlock()
                    return
                }
                isCancelled = true
                let upstream = upstream
                self.upstream = nil
                lock.unlock()

                upstream?.cancel()
                subject.send(completion: .finished)
            }
        }

        private struct PendingEnrollment {
            let loginIdPublisher: AnyPublisher<String, Never>
            let authTokenPublisher: AnyPublisher<String, Never>
            let force: Bool
        }

        private enum Lifecycle {
            case inactive
            case active
            case superseded
            case terminated
        }
        
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
                    force: Bool) -> OwnID.EnrollEventPublisher {
            assert(Thread.isMainThread)
            let publisher = prepareEnrollment(loginIdPublisher: loginIdPublisher,
                                              authTokenPublisher: authTokenPublisher,
                                              force: force)
            startPreparedEnrollment()
            return publisher
        }

        func prepareEnrollment(loginIdPublisher: AnyPublisher<String, Never>,
                               authTokenPublisher: AnyPublisher<String, Never>,
                               force: Bool,
                               inputBridges: [InputBridge] = []) -> OwnID.EnrollEventPublisher {
            assert(Thread.isMainThread)
            guard lifecycle == .inactive else { return eventPublisher }
            lifecycle = .active
            self.inputBridges = inputBridges
            pendingEnrollment = PendingEnrollment(
                loginIdPublisher: loginIdPublisher
                    .receive(on: DispatchQueue.main)
                    .eraseToAnyPublisher(),
                authTokenPublisher: authTokenPublisher
                    .receive(on: DispatchQueue.main)
                    .eraseToAnyPublisher(),
                force: force
            )
            return eventPublisher
        }

        func startPreparedEnrollment() {
            assert(Thread.isMainThread)
            guard lifecycle == .active, let pendingEnrollment else { return }
            self.pendingEnrollment = nil
            store.send(.addPublishers(loginIdPublisher: pendingEnrollment.loginIdPublisher,
                                      authTokenPublisher: pendingEnrollment.authTokenPublisher,
                                      force: pendingEnrollment.force))
        }

        func cancelForReplacement() {
            assert(Thread.isMainThread)
            markSuperseded()
            finishSuperseded()
        }

        func markSuperseded() {
            assert(Thread.isMainThread)
            guard lifecycle == .active else { return }
            lifecycle = .superseded
            store.invalidateActionsAndEffects()
        }

        private func finishSuperseded() {
            assert(Thread.isMainThread)
            guard lifecycle == .superseded else { return }
            terminate(with: .failure(.flowCancelled(flow: .enroll)))
        }

        func finish(with result: Result<Void, OwnID.CoreSDK.Error>) {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self.finish(with: result) }
                return
            }
            guard lifecycle == .active else { return }
            terminate(with: result)
        }

        private func terminate(with result: Result<Void, OwnID.CoreSDK.Error>) {
            assert(Thread.isMainThread)
            lifecycle = .terminated
            pendingEnrollment = nil

            let authManager = store.value.authManager
            let enrollViewStore = store.value.enrollViewStore
            let authManagerStore = store.value.authManagerStore
            let inputBridges = inputBridges
            self.inputBridges.removeAll()

            bag.removeAll()
            if #available(iOS 16.0, *) {
                authManager?.cancel()
            }
            store.cancel()
            enrollViewStore?.cancel()
            authManagerStore?.cancel()
            inputBridges.forEach { $0.cancel() }

            switch result {
            case .success:
                resultPublisher.send(())
                resultPublisher.send(completion: .finished)
            case .failure(let error):
                resultPublisher.send(completion: .failure(error))
            }
        }
        
        private func setupEventPublisher() {
            store
                .actionsPublisher
                .sink { [weak self] action in
                    switch action {
                    case .fidoUnavailable(let error):
                        self?.finish(with: .failure(error))
                    case .skip(let error):
                        self?.finish(with: .failure(error ?? .flowCancelled(flow: .enroll)))
                    case .error(let wrapper):
                        self?.finish(with: .failure(wrapper.error))
                    case .cancelled(let flow):
                        let error = OwnID.CoreSDK.Error.flowCancelled(flow: flow)
                        self?.finish(with: .failure(error))
                    case .finished:
                        self?.finish(with: .success(()))
                    default:
                        break
                    }
                }
                .store(in: &bag)
        }
    }
}
