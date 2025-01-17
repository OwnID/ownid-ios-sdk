import Foundation
import Combine

extension OwnID.FlowsSDK.RegisterView.ViewModel {
    enum State: CaseIterable {
        case initial
        case coreVM
        case ownidCreated
    }
}

extension OwnID.FlowsSDK.RegisterView.ViewModel.State {
    var buttonState: OwnID.UISDK.ButtonState {
        switch self {
        case .initial, .coreVM:
            return .enabled
            
        case .ownidCreated:
            return .activated
        }
    }
    
    var isLoading: Bool {
        switch self {
        case .initial, .ownidCreated:
            return false
            
        case .coreVM:
            return true
        }
    }
}

extension OwnID.FlowsSDK.RegisterView.ViewModel {
    public struct EmptyRegisterParameters: RegisterParameters {
        public init () { }
    }
    
    struct RegistrationData {
        fileprivate var payload: OwnID.CoreSDK.Payload?
        fileprivate var persistedLoginId: OwnID.CoreSDK.LoginID = ""
    }
}

public extension OwnID.FlowsSDK.RegisterView {
    final class ViewModel: ObservableObject {
        @Published private(set) var state = State.initial
        
        @Published public var shouldShowTooltip = false
        
        private var bag = Set<AnyCancellable>()
        private var coreViewModelBag = Set<AnyCancellable>()
        private let integrationResultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.RegistrationEvent, OwnID.CoreSDK.Error>, Never>()
        private let flowResultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.RegistrationFlowEvent, OwnID.CoreSDK.Error>, Never>()
        private let registrationPerformer: RegistrationPerformer?
        private var registrationData = RegistrationData()
        private let loginPerformer: LoginPerformer?
        private var loginId = ""
        var coreViewModel: OwnID.CoreSDK.CoreViewModel!
        var currentMetadata: OwnID.CoreSDK.CurrentMetricInformation?
        let eventService: EventProtocol
        
        var hasIntegration: Bool {
            registrationPerformer != nil
        }
        
        @available(*, deprecated, renamed: "integrationEventPublisher")
        public var eventPublisher: OwnID.RegistrationPublisher {
            integrationResultPublisher.eraseToAnyPublisher()
        }
        
        public var integrationEventPublisher: OwnID.RegistrationPublisher {
            integrationResultPublisher.eraseToAnyPublisher()
        }
        
        public var flowEventPublisher: OwnID.RegistrationFlowPublisher {
            flowResultPublisher.eraseToAnyPublisher()
        }
        
        public init(registrationPerformer: RegistrationPerformer? = nil,
                    loginPerformer: LoginPerformer? = nil,
                    loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher,
                    eventService: EventProtocol = OwnID.CoreSDK.eventService) {
            self.registrationPerformer = registrationPerformer
            self.loginPerformer = loginPerformer
            self.eventService = eventService
            loginIdPublisher.assign(to: \.loginId, on: self).store(in: &bag)
            loginIdPublisher
                .removeDuplicates()
                .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
                .sink { [unowned self] loginId in
                    shouldShowTooltip = shouldShowTooltipDefault(loginId: loginId)
            }
            .store(in: &bag)
                // Delay the task by 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.sendMetric()
            }
        }
        
        private func shouldShowTooltipDefault(loginId: String?) -> Bool {
            let configuration = OwnID.CoreSDK.shared.store.value.configuration
            guard let loginId,
                  let loginIdSettings = configuration?.loginIdSettings else {
                return false
            }
            let loginIdObject = OwnID.CoreSDK.LoginId(value: loginId, settings: loginIdSettings)
            return loginIdObject.isValid
        }
        
        private func sendMetric() {
            if let currentMetadata {
                OwnID.CoreSDK.shared.currentMetricInformation = currentMetadata
            }
            eventService.sendMetric(.trackMetric(action: .loaded,
                                                 category: .registration))
        }
        
        public func register(registerParameters: RegisterParameters = EmptyRegisterParameters()) {
            guard let payload = registrationData.payload else {
                let message = OwnID.CoreSDK.ErrorMessage.payloadMissing
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message))
                OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self).log()
                handle(error, context: nil)
                return
            }
            let config = OwnID.FlowsSDK.RegistrationConfiguration(payload: payload,
                                                                  loginId: loginId)
            if let registrationPerformer {
                registrationPerformer.register(configuration: config, parameters: registerParameters)
                    .sink { [unowned self] completion in
                        if case .failure(let error) = completion {
                            handle(error, context: payload.context)
                        }
                    } receiveValue: { [unowned self] registrationResult in
                        if let loginId = payload.loginId {
                            OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId,
                                                            authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: registrationResult.authType))
                        }
                        integrationResultPublisher.send(.success(.userRegisteredAndLoggedIn(registrationResult: registrationResult.operationResult, authType: registrationResult.authType)))
                        resetDataAndState()
                    }
                    .store(in: &bag)
            }
        }
        
        private func registerWithoutIntegration(payload: OwnID.CoreSDK.Payload) {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Registration without integration response", type: Self.self)
            
            if let loginId = payload.loginId {
                OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId,
                                                authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: payload.authType))
            }
            flowResultPublisher.send(.success(.response(loginId: payload.loginId ?? "", payload: payload, authType: payload.authType)))
        }
        
        /// Reset visual state and any possible data
        public func resetDataAndState(isResettingToInitialState: Bool = true) {
            registrationData = RegistrationData()
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
            if case .coreVM = state {
                resetToInitialState()
                return
            }
            if case .ownidCreated = state {
                eventService.sendMetric(.clickMetric(action: .undo,
                                                     category: .registration,
                                                     context: registrationData.payload?.context,
                                                     loginId: loginId))
                resetToInitialState()
                hasIntegration ? integrationResultPublisher.send(.success(.resetTapped)) : flowResultPublisher.send(.success(.resetTapped))
                return
            }
            if let payload = registrationData.payload, registrationData.payload?.loginId == loginId {
                state = .ownidCreated
                
                eventService.sendMetric(.trackMetric(action: .registered,
                                                     category: .registration,
                                                     context: payload.context,
                                                     loginId: loginId,
                                                     authType: payload.authType?.rawValue))
                
                if hasIntegration {
                    integrationResultPublisher.send(.success(.readyToRegister(loginId: loginId, authType: registrationData.payload?.authType)))
                } else {
                    flowResultPublisher.send(.success(.response(loginId: loginId, payload: payload, authType: payload.authType)))
                }
                return
            }
            let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForRegister(loginId: loginId)
            self.coreViewModel = coreViewModel
            subscribe(to: coreViewModel.eventPublisher, persistingLoginId: loginId)
            state = .coreVM
            
            /// On iOS 13, this `asyncAfter` is required to make sure that subscription created by the time events start to
            /// be passed to publiser.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                coreViewModel.start()
            }
        }
        
        func subscribe(to eventsPublisher: OwnID.CoreSDK.CoreViewModel.EventPublisher, persistingLoginId: OwnID.CoreSDK.LoginID) {
            registrationData.persistedLoginId = persistingLoginId
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
                        OwnID.CoreSDK.logger.log(level: .debug, type: Self.self)
                        switch payload.responseType {
                        case .registrationInfo:
                            self.registrationData.payload = payload
                            state = .ownidCreated
                            if let loginId = registrationData.payload?.loginId {
                                registrationData.persistedLoginId = loginId
                                self.loginId = loginId
                            }
                            
                            eventService.sendMetric(.trackMetric(action: .registered,
                                                                 category: .registration,
                                                                 context: payload.context,
                                                                 loginId: loginId,
                                                                 authType: payload.authType?.rawValue))
                            
                            if hasIntegration {
                                integrationResultPublisher.send(.success(.readyToRegister(loginId: payload.loginId, authType: payload.authType)))
                            } else {
                                registerWithoutIntegration(payload: payload)
                            }
                            
                        case .session:
                            processLogin(payload: payload)
                        }
                        
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
                } receiveValue: { [unowned self] _ in
                    let configuration = OwnID.CoreSDK.shared.store.value.configuration
                    var validLoginIdFormat: Bool?
                    if let loginIdSettings = configuration?.loginIdSettings {
                        validLoginIdFormat = OwnID.CoreSDK.LoginId(value: loginId, settings: loginIdSettings).isValid
                    }
                    if state != .ownidCreated {
                        eventService.sendMetric(.clickMetric(action: .click,
                                                             category: .registration,
                                                             hasLoginId: !loginId.isEmpty,
                                                             validLoginIdFormat: validLoginIdFormat))
                    }
                    skipPasswordTapped(loginId: loginId)
                }
                .store(in: &bag)
        }
    }
}

private extension OwnID.FlowsSDK.RegisterView.ViewModel {
    
    func processLogin(payload: OwnID.CoreSDK.Payload) {
        eventService.sendMetric(.trackMetric(action: .loggedIn,
                                             category: .registration,
                                             context: payload.context,
                                             loginId: loginId,
                                             authType: payload.authType?.rawValue))
        
        if let loginPerformer {
            let loginPerformerPublisher = loginPerformer.login(payload: payload, loginId: loginId)
            loginPerformerPublisher
                .sink { [unowned self] completion in
                    if case .failure(let error) = completion {
                        handle(error, context: payload.context)
                    }
                } receiveValue: { [unowned self] registerResult in
                    state = .ownidCreated
                    integrationResultPublisher.send(.success(.userRegisteredAndLoggedIn(registrationResult: registerResult.operationResult, authType: registerResult.authType)))
                    resetDataAndState(isResettingToInitialState: false)
                }
                .store(in: &bag)
        } else {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Login without integration response", type: Self.self)
            
            state = .ownidCreated
            flowResultPublisher.send(.success(.response(loginId: loginId, payload: payload, authType: payload.authType)))
            resetDataAndState(isResettingToInitialState: false)
        }
    }
    
    func handle(_ error: OwnID.CoreSDK.Error, context: String?) {
        switch error {
        case .userError:
            let errorMessage = error.localizedDescription
            eventService.sendMetric(.errorMetric(action: .error,
                                                 category: .registration,
                                                 context: context,
                                                 loginId: loginId,
                                                 errorMessage: errorMessage,
                                                 errorCode: error.metricErrorCode))
        case .integrationError:
            break
        case .flowCancelled:
            eventService.sendMetric(.errorMetric(action: .cancelFlow,
                                                 category: .registration,
                                                 context: context,
                                                 loginId: loginId,
                                                 errorMessage: OwnID.CoreSDK.AnalyticActionType.cancelFlow.actionValue,
                                                 errorCode: error.metricErrorCode))
        }
        
        resetToInitialState()
        
        hasIntegration ? integrationResultPublisher.send(.failure(error)) : flowResultPublisher.send(.failure(error))
    }
}
