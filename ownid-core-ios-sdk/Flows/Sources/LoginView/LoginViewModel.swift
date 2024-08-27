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
        private let integrationResultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.LoginEvent, OwnID.CoreSDK.Error>, Never>()
        private let flowResultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.LoginFlowEvent, OwnID.CoreSDK.Error>, Never>()
        private let loginPerformer: LoginPerformer?
        private var payload: OwnID.CoreSDK.Payload?
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
            loginIdPublisher.assign(to: \.loginId, on: self).store(in: &bag)
        }
        
        /// Reset visual state and any possible data from web flow
        public func resetDataAndState(isResettingToInitialState: Bool = true) {
            payload = .none
            resetToInitialState(isResettingToInitialState: isResettingToInitialState)
        }
        
        /// Reset visual state
        public func resetToInitialState(isResettingToInitialState: Bool = true) {
            if isResettingToInitialState {
                state = .initial
            }
            coreViewModel?.cancel()
            coreViewModelBag.forEach { $0.cancel() }
            coreViewModelBag.removeAll()
            coreViewModel = .none
        }
        
        func skipPasswordTapped(loginId: String) {
            switch state {
            case .initial:
                DispatchQueue.main.async { [self] in
                    let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForLogIn(loginId: loginId, 
                                                                                         loginType: loginType)
                    self.coreViewModel = coreViewModel
                    subscribe(to: coreViewModel.eventPublisher)
                    state = .coreVM
                    
                    /// On iOS 13, this `asyncAfter` is required to make sure that subscription created by the time events start to
                    /// be passed to publiser.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        coreViewModel.start()
                    }
                }
                
            case .coreVM:
                resetToInitialState()
                
            case .loggedIn:
                break
            }
        }
        
        func subscribe(to eventsPublisher: OwnID.CoreSDK.CoreViewModel.EventPublisher) {
            coreViewModelBag.forEach { $0.cancel() }
            coreViewModelBag.removeAll()
            eventsPublisher
                .sink { [unowned self] completion in
                    if case .failure(let error) = completion {
                        handle(error, context: OwnID.CoreSDK.logger.context)
                    }
                } receiveValue: { [unowned self] event in
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
                .sink { _ in
                } receiveValue: { [unowned self] event in
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
                    skipPasswordTapped(loginId: loginId)
                }
                .store(in: &bag)
        }
    }
}

private extension OwnID.FlowsSDK.LoginView.ViewModel {
    func process(payload: OwnID.CoreSDK.Payload) {
        self.payload = payload
        
        eventService.sendMetric(.trackMetric(action: .loggedIn,
                                             category: .login,
                                             context: payload.context,
                                             loginId: loginId,
                                             loginType: loginType,
                                             authType: payload.authType?.rawValue))
        
        if let loginPerformer {
            let loginPerformerPublisher = loginPerformer.login(payload: payload, loginId: loginId)
            loginPerformerPublisher
                .sink { [unowned self] completion in
                    if case .failure(let error) = completion {
                        handle(error, context: payload.context)
                    }
                } receiveValue: { [unowned self] loginResult in
                    if let loginId = payload.loginId {
                        OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId, 
                                                        authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: loginResult.authType))
                    }
                    integrationResultPublisher.send(.success(.loggedIn(loginResult: loginResult.operationResult, authType: loginResult.authType)))
                    resetDataAndState()
                }
                .store(in: &bag)
        } else {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Login without integration response", type: Self.self)
                        
            if let loginId = payload.loginId {
                OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId,
                                                authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: payload.authType))
            }
            flowResultPublisher.send(.success(.response(loginId: loginId, payload: payload, authType: payload.authType)))
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
