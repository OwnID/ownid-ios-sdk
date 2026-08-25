import Foundation
import Combine

extension OwnID.FlowsSDK.LoginView.ViewModel {
    enum State {
        case initial
        case coreVM
        case loggedIn
    }
}

extension OwnID.FlowsSDK.LoginView.ViewModel.State {
    var buttonState: OwnID.UISDK.ButtonState {
        switch self {
        case .initial, .coreVM:
            return .enabled
            
        case .loggedIn:
            return .activated
        }
    }
    
    var isLoading: Bool {
        switch self {
        case .coreVM:
            return true
            
        case .loggedIn, .initial:
            return false
        }
    }
}

public extension OwnID.FlowsSDK.LoginView {
    final class ViewModel: ObservableObject {
        @Published private(set) var state = State.initial
        @Published public var shouldShowTooltip = true
        
        private var bag = Set<AnyCancellable>()
        private var coreViewModelBag = Set<AnyCancellable>()
        private var integrationPerformerBag = Set<AnyCancellable>()
        private lazy var buttonTapAction = OwnID.UISDK.DebouncedAction { [weak self] in self?.buttonTapped() }
        private let integrationResultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.LoginEvent, OwnID.CoreSDK.Error>, Never>()
        private let flowResultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.LoginFlowEvent, OwnID.CoreSDK.Error>, Never>()
        private let loginPerformer: LoginPerformer?
        private var loginId = ""
        private let loginType: OwnID.CoreSDK.LoginType
        var coreViewModel: OwnID.CoreSDK.CoreViewModel!
        var currentMetadata: OwnID.CoreSDK.CurrentMetricInformation?
        let eventService: EventProtocol
        
        var hasIntegration: Bool {
            loginPerformer != nil
        }
        
        @available(*, deprecated, renamed: "integrationEventPublisher")
        public var eventPublisher: OwnID.LoginPublisher {
            integrationResultPublisher.eraseToAnyPublisher()
        }
        
        public var integrationEventPublisher: OwnID.LoginPublisher {
            integrationResultPublisher.eraseToAnyPublisher()
        }
        
        public var flowEventPublisher: OwnID.LoginFlowPublisher {
            flowResultPublisher.eraseToAnyPublisher()
        }
        
        public init(loginPerformer: LoginPerformer? = nil,
                    loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher,
                    loginType: OwnID.CoreSDK.LoginType = .standard,
                    eventService: EventProtocol = OwnID.CoreSDK.eventService) {
            self.loginPerformer = loginPerformer
            self.loginType = loginType
            self.eventService = eventService
            updateLoginIdPublisher(loginIdPublisher)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.sendMetric()
            }
        }
        
        private func sendMetric() {
            if let currentMetadata {
                OwnID.CoreSDK.shared.currentMetricInformation = currentMetadata
            }
            eventService.sendMetric(.trackMetric(action: .loaded,
                                                 category: .login,
                                                 loginType: loginType))
        }
        
        public func updateLoginIdPublisher(_ loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher) {
            loginIdPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.loginId = $0 }
                .store(in: &bag)
        }
        
        /// Reset visual state and any possible data
        public func resetDataAndState(isResettingToInitialState: Bool = true) {
            resetToInitialState(isResettingToInitialState: isResettingToInitialState)
        }
        
        /// Reset visual state
        public func resetToInitialState(isResettingToInitialState: Bool = true) {
            buttonTapAction.cancelPending()
            if isResettingToInitialState {
                state = .initial
            }
            coreViewModel?.cancel()
            coreViewModelBag.removeAll()
            integrationPerformerBag.removeAll()
            coreViewModel = .none
        }
        
        func skipPasswordTapped(loginId: String) {
            switch state {
            case .initial:
                let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForLogIn(loginId: loginId,
                                                                                     loginType: loginType)
                self.coreViewModel = coreViewModel
                subscribe(to: coreViewModel.eventPublisher)
                state = .coreVM
                coreViewModel.start()
                
            case .coreVM:
                resetToInitialState()
                
            case .loggedIn:
                break
            }
        }
        
        func subscribe(to eventsPublisher: OwnID.CoreSDK.CoreViewModel.EventPublisher) {
            coreViewModelBag.removeAll()
            eventsPublisher
                .sink { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let error) = completion {
                        handle(error, context: OwnID.CoreSDK.logger.context)
                    }
                } receiveValue: { [weak self] event in
                    guard let self = self else { return }
                    switch event {
                    case .success(let payload):
                        process(payload: payload)
                        
                    case .cancelled(let flow):
                        let error = OwnID.CoreSDK.Error.flowCancelled(flow: flow)
                        handle(error, context: OwnID.CoreSDK.logger.context)

                    case .loading:
                        hasIntegration ? integrationResultPublisher.send(.success(.loading)) : flowResultPublisher.send(.success(.loading))
                    }
                }
                .store(in: &coreViewModelBag)
        }
        
        /// Used for custom button setup. Custom button sends events through this publisher
        /// and by doing that invokes flow.
        /// - Parameter buttonEventPublisher: publisher to subscribe to
        public func subscribe(to buttonEventPublisher: OwnID.UISDK.EventPubliser) {
            buttonEventPublisher
                .receive(on: DispatchQueue.main)
                .sink { _ in
                } receiveValue: { [weak self] _ in
                    self?.buttonTapped()
                }
                .store(in: &bag)
        }

        func buttonTapped() {
            if state == .initial {
                let configuration = OwnID.CoreSDK.shared.store.value.configuration
                var validLoginIdFormat: Bool?
                if let loginIdSettings = configuration?.loginIdSettings {
                    validLoginIdFormat = OwnID.CoreSDK.LoginId(value: loginId, settings: loginIdSettings).isValid
                }
                eventService.sendMetric(.clickMetric(action: .click,
                                                     category: .login,
                                                     hasLoginId: !loginId.isEmpty,
                                                     loginType: loginType,
                                                     validLoginIdFormat: validLoginIdFormat))
            }
            var loginId = loginId
            if loginId.isBlank, let savedLoginId = OwnID.CoreSDK.DefaultsLoginIdSaver.loginId(), !savedLoginId.isBlank {
                loginId = savedLoginId
            }
            skipPasswordTapped(loginId: loginId)
        }

        func buttonTappedDebounced() {
            buttonTapAction.send()
        }
        
        /// Initiates an OwnID login flow if no other flow is active.
        ///
        /// - If `onlyReturningUser` is false, the authentication flow will start for the given `loginId`. If no `loginId` is provided, a prompt is displayed to get it and continue.
        /// - If `onlyReturningUser` is true, the authentication flow starts only for a previously logged in user (the `loginId` parameter is ignored). If no such user exists, the flow will not start.
        ///
        /// - Parameters:
        ///   - loginId: Optional user login ID (default `""`).
        ///   - onlyReturningUser: If true, only attempts a returning user flow (default `false`).
        /// - Returns: `true` if the flow starts, otherwise `false`.
        @discardableResult
        public func auth(loginId: String = "", onlyReturningUser: Bool = false) -> Bool {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Invoked auth", type: Self.self)
            
            if onlyReturningUser {
                guard let savedLoginId = OwnID.CoreSDK.DefaultsLoginIdSaver.loginId(), !savedLoginId.isEmpty else {
                    return false
                }
                
                return startFlow(loginId: savedLoginId)
            } else {
                return startFlow(loginId: loginId)
            }
        }

        private func startFlow(loginId: String) -> Bool {
            if Thread.isMainThread {
                return startIfIdle(loginId: loginId)
            } else {
                return DispatchQueue.main.sync { [weak self] in
                    self?.startIfIdle(loginId: loginId) ?? false
                }
            }
        }

        private func startIfIdle(loginId: String) -> Bool {
            assert(Thread.isMainThread)
            guard state == .initial else { return false }
            skipPasswordTapped(loginId: loginId)
            return true
        }
    }
}

private extension OwnID.FlowsSDK.LoginView.ViewModel {
    func process(payload: OwnID.CoreSDK.Payload) {
        let responseLoginId = payload.loginId ?? ""
        loginId = responseLoginId
        
        eventService.sendMetric(.trackMetric(action: .loggedIn,
                                             category: .login,
                                             context: payload.context,
                                             loginId: responseLoginId,
                                             loginType: loginType,
                                             authType: payload.authType?.rawValue))
        
        if let loginPerformer {
            integrationPerformerBag.removeAll()
            let loginPerformerPublisher = loginPerformer.login(payload: payload, loginId: responseLoginId)
            loginPerformerPublisher
                .prefix(1)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let error) = completion {
                        handle(error, context: payload.context)
                    }
                } receiveValue: { [weak self] loginResult in
                    guard let self = self else { return }
                    if !responseLoginId.isBlank {
                        OwnID.CoreSDK.LoginIdSaver.save(loginId: responseLoginId,
                                                        authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: loginResult.authType))
                    }
                    integrationResultPublisher.send(.success(.loggedIn(loginResult: loginResult.operationResult, authType: loginResult.authType, authToken: payload.authToken)))
                    resetDataAndState()
                }
                .store(in: &integrationPerformerBag)
        } else {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Login without integration response", type: Self.self)
                        
            if !responseLoginId.isBlank {
                OwnID.CoreSDK.LoginIdSaver.save(loginId: responseLoginId,
                                                authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: payload.authType))
            }
            flowResultPublisher.send(.success(.response(loginId: responseLoginId, payload: payload, authType: payload.authType, authToken: payload.authToken)))
            resetDataAndState()
        }
    }
    
    func handle(_ error: OwnID.CoreSDK.Error, context: String?) {
        switch error {
        case .userError:
            let errorMessage = error.localizedDescription
            eventService.sendMetric(.errorMetric(action: .error,
                                                 category: .login,
                                                 context: context,
                                                 loginType: loginType,
                                                 errorMessage: errorMessage,
                                                 errorCode: error.metricErrorCode))
        case .integrationError:
            break
        case .flowCancelled:
            eventService.sendMetric(.errorMetric(action: .cancelFlow,
                                                 category: .login,
                                                 context: context,
                                                 loginId: loginId,
                                                 errorMessage: OwnID.CoreSDK.AnalyticActionType.cancelFlow.actionValue,
                                                 errorCode: error.metricErrorCode))
        }
        
        resetToInitialState()
        
        hasIntegration ? integrationResultPublisher.send(.failure(error)) : flowResultPublisher.send(.failure(error))
    }
}
