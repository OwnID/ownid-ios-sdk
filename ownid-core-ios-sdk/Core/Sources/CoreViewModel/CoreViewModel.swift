import Foundation
import Combine

extension OwnID.CoreSDK {
    final class CoreViewModel: ObservableObject {
        @Published var store: Store<State, Action>
        private let resultPublisher = PassthroughSubject<Event, OwnID.CoreSDK.Error>()
        private var bag = Set<AnyCancellable>()
        private var isTerminated = false
        private var redirectContext: OwnID.CoreSDK.Context?
        
        var eventPublisher: EventPublisher { resultPublisher.receive(on: DispatchQueue.main).eraseToAnyPublisher() }
        
        init(type: OwnID.CoreSDK.RequestType,
             loginId: String,
             loginType: OwnID.CoreSDK.LoginType? = nil,
             supportedLanguages: OwnID.CoreSDK.Languages,
             clientConfiguration: LocalConfiguration?) {
            let initialState = State(configuration: clientConfiguration,
                                     loginId: loginId,
                                     type: type,
                                     loginType: loginType,
                                     supportedLanguages: supportedLanguages)
            let store = Store(
                initialValue: initialState,
                reducer: Self.reducer
            )
            self.store = store
            
            let idCollectViewStore = self.store.view(
                value: { _ in OwnID.UISDK.IdCollect.ViewState() },
                action: { .idCollectView($0) },
                action: { globalAction in
                    switch globalAction {
                    case .error(let wrapper):
                        switch wrapper.error {
                        case .userError(let errorModel):
                            return .error(errorModel, flowFinished: wrapper.flowFinished)
                        default:
                            return .error(OwnID.CoreSDK.UserErrorModel(message: OwnID.CoreSDK.ErrorMessage.requestError), 
                                          flowFinished: wrapper.flowFinished)
                        }
                    default:
                        break
                    }
                    return nil
                },
                reducer: { OwnID.UISDK.IdCollect.viewModelReducer(state: &$0, action: $1) }
            )
            let oneTimePasswordViewStore = self.store.view(
                value: { OwnID.UISDK.OneTimePassword.ViewState(type: $0.type) },
                action: { .oneTimePasswordView($0) },
                action: { globalAction in
                    switch globalAction {
                    case .error(let wrapper):
                        switch wrapper.error {
                        case .userError(let errorModel):
                            return .error(errorModel, flowFinished: wrapper.flowFinished)
                        default:
                            return .error(OwnID.CoreSDK.UserErrorModel(message: OwnID.CoreSDK.ErrorMessage.requestError), flowFinished:
                                            wrapper.flowFinished)
                        }
                    case .sameStep:
                        return .stopLoading
                    case .notYouCancel(let operationType):
                        return .notYouCancel(operationType: operationType)
                    case .success:
                        return .success
                    default:
                        break
                    }
                    return .none
                },
                reducer: { OwnID.UISDK.OneTimePassword.viewModelReducer(state: &$0, action: $1) }
            )
            let browserStore = self.store.view(value: { _ in BrowserOpenerViewModel.State() } , action: { .browserVM($0) })
            let authManagerStore = self.store.view(value: { _ in AuthManager.State() },
                                                   action: { .authManager($0) })
            self.store.send(.addToState(browserViewModelStore: browserStore,
                                        authStore: authManagerStore,
                                        oneTimePasswordStore: oneTimePasswordViewStore,
                                        idCollectViewStore: idCollectViewStore))
            setupEventPublisher()
        }

        deinit {
            guard let redirectContext else { return }
            self.redirectContext = nil
            OwnID.CoreSDK.shared.unregisterRedirectContext(redirectContext)
        }
        
        public func start() {
            if (store.value.configuration != nil) {
                store.send(.addToStateShouldStartInitRequest(value: false))
                store.send(.sendInitialRequest)
            } else {
                OwnID.CoreSDK.shared.requestConfiguration()
                store.send(.addToStateShouldStartInitRequest(value: true))
                resultPublisher.send(.loading)
            }
        }
        
        public func cancel() {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { self.cancel() }
                return
            }
            guard beginTermination() else { return }

            if #available(iOS 16.0, *) {
                store.value.authManager?.cancel()
            }
            store.value.browserViewModel?.cancel()
            store.send(.cancelled)
            finishResources()
        }
        
        func subscribeToURL(publisher: AnyPublisher<RedirectEvent, Never>) {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    guard let self, event.context == redirectContext else { return }
                    switch event.result {
                    case .success:
                        store.send(.sendStatusRequest)
                    case .failure(let error):
                        store.send(.error(OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self)))
                    }
                }
                .store(in: &bag)
        }
        
        func subscribeToConfiguration(publisher: AnyPublisher<ConfigurationLoadingEvent, Never>) {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    guard let self = self else { return }
                    switch event {
                        
                    case .loaded(let configuration):
                        store.send(.addToStateConfig(config: configuration))
                        
                    case .error(let error):
                        store.send(.error(OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self)))
                    }
                }
                .store(in: &bag)
        }
        
        private var internalStatesChange = [String]()
        
        private func logInternalStates() {
            let states = internalStatesLog(states: internalStatesChange)
            OwnID.CoreSDK.logger.log(level: .debug, message: states, type: Self.self)
            internalStatesChange.removeAll()
        }
        
        private func internalStatesLog(states: [String]) -> String {
            "\(Self.self): finished states ➡️ \(internalStatesChange)"
        }
        
        private func setupEventPublisher() {
            store
                .actionsPublisher
                .sink { [weak self] action in
                    guard let self = self else { return }
                    switch action {
                    case .sendInitialRequest:
                        internalStatesChange.append(String(describing: action))
                        resultPublisher.send(.loading)
                        
                    case .initialRequestLoaded(let response):
                        internalStatesChange.append(action.debugDescription)
                        updateRedirectContext(response.context)

                    case .idCollect,
                            .oneTimePassword,
                            .addErrorToInternalStates,
                            .sendStatusRequest,
                            .addToState,
                            .addToStateConfig,
                            .addToStateShouldStartInitRequest,
                            .idCollectView,
                            .authManager,
                            .oneTimePasswordView,
                            .browserVM,
                            .webApp,
                            .codeResent,
                            .authManagerCancelled,
                            .cancelled,
                            .sameStep,
                            .notYouCancel:
                        internalStatesChange.append(action.debugDescription)

                    case .fido2Authorize, .success:
                        internalStatesChange.append(action.debugDescription)
                        OwnID.UISDK.PopupManager.dismissPopup()
                        
                    case let .statusRequestLoaded(payload):
                        internalStatesChange.append(String(describing: action))
                        finish(with: .event(.success(payload)))
                        
                    case .error(let wrapper):
                        internalStatesChange.append(String(describing: action))
                        if wrapper.isOnUI {
                            let category: EventCategory
                            switch store.value.type {
                            case .login:
                                category = .login
                            case .register:
                                category = .registration
                            }
                            
                            OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .error,
                                                                               category: category,
                                                                               context: OwnID.CoreSDK.logger.context,
                                                                               errorMessage: wrapper.error.localizedDescription,
                                                                               errorCode: wrapper.error.metricErrorCode))
                        }

                        if !wrapper.isOnUI {
                            finish(with: .failure(wrapper.error))
                        }
                        
                    case .stopRequestLoaded(let flow):
                        internalStatesChange.append(String(describing: action))
                        finish(with: .event(.cancelled(flow: flow)))
                    }
                }
                .store(in: &bag)
        }
        
        private enum FinishResult {
            case event(Event)
            case failure(OwnID.CoreSDK.Error)
        }

        private func finish(with result: FinishResult) {
            guard beginTermination() else { return }
            finishResources()

            switch result {
            case .event(let event):
                resultPublisher.send(event)
            case .failure(let error):
                resultPublisher.send(completion: .failure(error))
            }
        }

        private func beginTermination() -> Bool {
            guard !isTerminated else { return false }
            isTerminated = true
            return true
        }

        func updateRedirectContext(_ context: OwnID.CoreSDK.Context) {
            assert(Thread.isMainThread)
            guard redirectContext != context else { return }
            if let redirectContext {
                OwnID.CoreSDK.shared.unregisterRedirectContext(redirectContext)
            }
            redirectContext = context
            OwnID.CoreSDK.shared.registerRedirectContext(context)
        }

        private func finishResources() {
            logInternalStates()
            if let redirectContext {
                OwnID.CoreSDK.shared.unregisterRedirectContext(redirectContext)
                self.redirectContext = nil
            }
            OwnID.UISDK.PopupManager.dismissPopup()
            if #available(iOS 16.0, *) {
                store.value.authManager?.cancel()
            }
            store.cancel()
            store.value.browserViewModelStore?.cancel()
            store.value.authManagerStore?.cancel()
            store.value.oneTimePasswordStore?.cancel()
            store.value.idCollectViewStore?.cancel()
            bag.removeAll()
        }
    }
}
