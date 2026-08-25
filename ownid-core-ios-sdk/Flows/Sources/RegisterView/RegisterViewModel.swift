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
    }
}

public extension OwnID.FlowsSDK.RegisterView {
    final class ViewModel: ObservableObject {
        @Published private(set) var state = State.initial
        
        @Published public var shouldShowTooltip = false
        
        private var bag = Set<AnyCancellable>()
        private var coreViewModelBag = Set<AnyCancellable>()
        private var integrationPerformerBag = Set<AnyCancellable>()
        private lazy var buttonTapAction = OwnID.UISDK.DebouncedAction { [weak self] in self?.buttonTapped() }
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
            loginIdPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.loginId = $0 }
                .store(in: &bag)
            loginIdPublisher
                .removeDuplicates()
                .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
                .sink { [weak self] loginId in
                    guard let self = self else { return }
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
            let responseLoginId = payload.loginId ?? ""
            let config = OwnID.FlowsSDK.RegistrationConfiguration(payload: payload,
                                                                  loginId: responseLoginId)
            if let registrationPerformer {
                integrationPerformerBag.removeAll()
                registrationPerformer.register(configuration: config, parameters: registerParameters)
                    .prefix(1)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] completion in
                        guard let self = self else { return }
                        if case .failure(let error) = completion {
                            handle(error, context: payload.context)
                        }
                    } receiveValue: { [weak self] registrationResult in
                        guard let self = self else { return }
                        if !responseLoginId.isBlank {
                            OwnID.CoreSDK.LoginIdSaver.save(loginId: responseLoginId,
                                                            authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: registrationResult.authType))
                        }
                        integrationResultPublisher.send(.success(.userRegisteredAndLoggedIn(registrationResult: registrationResult.operationResult, authType: registrationResult.authType, authToken: payload.authToken)))
                        resetDataAndState()
                    }
                    .store(in: &integrationPerformerBag)
            }
        }
        
        private func registerWithoutIntegration(payload: OwnID.CoreSDK.Payload, loginId: String) {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Registration without integration response", type: Self.self)
            
            if !loginId.isBlank {
                OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId,
                                                authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: payload.authType))
            }
            flowResultPublisher.send(.success(.response(loginId: loginId, payload: payload, authType: payload.authType, authToken: payload.authToken)))
        }
        
        /// Reset visual state and any possible data
        public func resetDataAndState(isResettingToInitialState: Bool = true) {
            registrationData = RegistrationData()
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
                    flowResultPublisher.send(.success(.response(loginId: loginId, payload: payload, authType: payload.authType, authToken: payload.authToken)))
                }
                return
            }
            let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForRegister(loginId: loginId)
            self.coreViewModel = coreViewModel
            subscribe(to: coreViewModel.eventPublisher)
            state = .coreVM
            coreViewModel.start()
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
                        OwnID.CoreSDK.logger.log(level: .debug, type: Self.self)
                        if let payloadLoginId = payload.loginId, !payloadLoginId.isBlank {
                            loginId = payloadLoginId
                        }
                        switch payload.responseType {
                        case .registrationInfo:
                            self.registrationData.payload = payload
                            state = .ownidCreated
                            
                            eventService.sendMetric(.trackMetric(action: .registered,
                                                                 category: .registration,
                                                                 context: payload.context,
                                                                 loginId: loginId,
                                                                 authType: payload.authType?.rawValue))
                            
                            if hasIntegration {
                                integrationResultPublisher.send(.success(.readyToRegister(loginId: payload.loginId, authType: payload.authType)))
                            } else {
                                registerWithoutIntegration(payload: payload, loginId: payload.loginId ?? "")
                            }
                            
                        case .session:
                            processLogin(payload: payload, loginId: payload.loginId ?? "")
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
                .receive(on: DispatchQueue.main)
                .sink { _ in
                } receiveValue: { [weak self] _ in
                    self?.buttonTapped()
                }
                .store(in: &bag)
        }

        func buttonTapped() {
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

        func buttonTappedDebounced() {
            buttonTapAction.send()
        }
    }
}

private extension OwnID.FlowsSDK.RegisterView.ViewModel {
    
    func processLogin(payload: OwnID.CoreSDK.Payload, loginId: String) {
        eventService.sendMetric(.trackMetric(action: .loggedIn,
                                             category: .registration,
                                             context: payload.context,
                                             loginId: loginId,
                                             authType: payload.authType?.rawValue))
        
        if let loginPerformer {
            integrationPerformerBag.removeAll()
            let loginPerformerPublisher = loginPerformer.login(payload: payload, loginId: loginId)
            loginPerformerPublisher
                .prefix(1)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let error) = completion {
                        handle(error, context: payload.context)
                    }
                } receiveValue: { [weak self] registerResult in
                    guard let self = self else { return }
                    state = .ownidCreated
                    if !loginId.isBlank {
                        OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId,
                                                        authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: registerResult.authType))
                    }
                    integrationResultPublisher.send(.success(.userRegisteredAndLoggedIn(registrationResult: registerResult.operationResult, authType: registerResult.authType, authToken: payload.authToken)))
                    resetDataAndState(isResettingToInitialState: false)
                }
                .store(in: &integrationPerformerBag)
        } else {
            OwnID.CoreSDK.logger.log(level: .debug, message: "Login without integration response", type: Self.self)
            
            state = .ownidCreated
            if !loginId.isBlank {
                OwnID.CoreSDK.LoginIdSaver.save(loginId: loginId,
                                                authMethod: OwnID.CoreSDK.AuthMethod.authMethod(from: payload.authType))
            }
            flowResultPublisher.send(.success(.response(loginId: loginId, payload: payload, authType: payload.authType, authToken: payload.authToken)))
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
