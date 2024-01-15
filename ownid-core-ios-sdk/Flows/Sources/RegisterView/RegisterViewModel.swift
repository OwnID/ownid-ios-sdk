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
        private enum Constants {
            static let sourceName = "OwnIdRegisterViewModel"
        }
        
        @Published private(set) var state = State.initial
        
        /// Checks loginId if it is valid for tooltip display. On each change of loginId, it
        /// determines  if tooltop should be shown. To change this behaviour, provide your value.
        public var shouldShowTooltipLogic: Bool?
        
        @Published public var shouldShowTooltip = false
        
        private var bag = Set<AnyCancellable>()
        private var coreViewModelBag = Set<AnyCancellable>()
        private let resultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.RegistrationEvent, OwnID.CoreSDK.Error>, Never>()
        private let registrationPerformer: RegistrationPerformer
        private var registrationData = RegistrationData()
        private let loginPerformer: LoginPerformer
        private var loginId = ""
        var coreViewModel: OwnID.CoreSDK.CoreViewModel!
        var currentMetadata: OwnID.CoreSDK.CurrentMetricInformation?
        let eventService: EventProtocol
        
        let sdkConfigurationName: String
        
        public var eventPublisher: OwnID.RegistrationPublisher {
            resultPublisher.eraseToAnyPublisher()
        }
        
        public init(registrationPerformer: RegistrationPerformer,
                    loginPerformer: LoginPerformer,
                    sdkConfigurationName: String,
                    loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher,
                    eventService: EventProtocol = OwnID.CoreSDK.eventService) {
            self.sdkConfigurationName = sdkConfigurationName
            self.registrationPerformer = registrationPerformer
            self.loginPerformer = loginPerformer
            self.eventService = eventService
            loginIdPublisher.assign(to: \.loginId, on: self).store(in: &bag)
            loginIdPublisher
                .removeDuplicates()
                .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
                .sink { [unowned self] loginId in
                    shouldShowTooltip = shouldShowTooltipLogic ?? shouldShowTooltipDefault(loginId: loginId)
            }
            .store(in: &bag)
            Task {
                // Delay the task by 1 second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                sendMetric()
            }
        }
        
        private func shouldShowTooltipDefault(loginId: String?) -> Bool {
            let configuration = OwnID.CoreSDK.shared.store.value.getOptionalConfiguration(for: sdkConfigurationName)
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
                                                 category: .registration,
                                                 context: registrationData.payload?.context,
                                                 loginId: loginId,
                                                 source: Constants.sourceName))
        }
        
        public func register(registerParameters: RegisterParameters = EmptyRegisterParameters()) {
            guard let payload = registrationData.payload else {
                let message = OwnID.CoreSDK.ErrorMessage.payloadMissing
                handle(.coreLog(error: .userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: message)), type: Self.self))
                return
            }
            let config = OwnID.FlowsSDK.RegistrationConfiguration(payload: payload,
                                                                  loginId: loginId)
            registrationPerformer.register(configuration: config, parameters: registerParameters)
                .sink { [unowned self] completion in
                    if case .failure(let error) = completion {
                        handle(error)
                        let errorMessage = error.error.localizedDescription
                        eventService.sendMetric(.errorMetric(action: .error(message: errorMessage),
                                                             category: .registration,
                                                             context: payload.context,
                                                             loginId: loginId,
                                                             errorMessage: errorMessage,
                                                             source: Constants.sourceName))
                    }
                } receiveValue: { [unowned self] registrationResult in
                    eventService.sendMetric(.trackMetric(action: .registered,
                                                         category: .registration,
                                                         context: payload.context,
                                                         loginId: loginId,
                                                         authType: registrationResult.authType,
                                                         source: Constants.sourceName))
                    if let loginId = payload.loginId {
                        OwnID.CoreSDK.DefaultsLoginIdSaver.save(loginId: loginId)
                    }
                    resultPublisher.send(.success(.userRegisteredAndLoggedIn(registrationResult: registrationResult.operationResult, authType: registrationResult.authType)))
                    resetDataAndState()
                }
                .store(in: &bag)
        }
        
        /// Reset visual state and any possible data from web flow
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
                                                     loginId: loginId,
                                                     source: Constants.sourceName))
                resetToInitialState()
                resultPublisher.send(.success(.resetTapped))
                return
            }
            if registrationData.payload != nil, registrationData.payload?.loginId == loginId {
                state = .ownidCreated
                resultPublisher.send(.success(.readyToRegister(loginId: loginId, authType: registrationData.payload?.authType)))
                return
            }
            let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForRegister(loginId: loginId, sdkConfigurationName: sdkConfigurationName)
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
                        handle(error)
                        OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .error(message: error.localizedDescription),
                                                                           category: .registration,
                                                                           context: OwnID.CoreSDK.logger.context,
                                                                           errorMessage: error.localizedDescription))
                    }
                } receiveValue: { [unowned self] event in
                    switch event {
                    case .success(let payload):
                        OwnID.CoreSDK.logger.log(level: .debug, Self.self)
                        switch payload.responseType {
                        case .registrationInfo:
                            self.registrationData.payload = payload
                            state = .ownidCreated
                            if let loginId = registrationData.payload?.loginId {
                                registrationData.persistedLoginId = loginId
                                self.loginId = loginId
                            }
                            resultPublisher.send(.success(.readyToRegister(loginId: registrationData.payload?.loginId, authType: registrationData.payload?.authType)))
                            
                        case .session:
                            processLogin(payload: payload)
                        }
                        
                    case .cancelled(let flow):
                        let error = OwnID.CoreSDK.Error.flowCancelled(flow: flow)
                        OwnID.CoreSDK.logger.log(level: .warning, message: error.localizedDescription, Self.self)
                        handle(OwnID.CoreSDK.CoreErrorLogWrapper(error: error))
                        
                    case .loading:
                        resultPublisher.send(.success(.loading))
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
                    eventService.sendMetric(.clickMetric(action: .click,
                                                         category: .registration,
                                                         context: registrationData.payload?.context,
                                                         hasLoginId: !loginId.isEmpty,
                                                         source: Constants.sourceName))
                    skipPasswordTapped(loginId: loginId)
                }
                .store(in: &bag)
        }
    }
}

private extension OwnID.FlowsSDK.RegisterView.ViewModel {
    
    func processLogin(payload: OwnID.CoreSDK.Payload) {
        let loginPerformerPublisher = loginPerformer.login(payload: payload, loginId: loginId)
        loginPerformerPublisher
            .sink { [unowned self] completion in
                if case .failure(let error) = completion {
                    handle(error)
                    let errorMessage = error.error.localizedDescription
                    eventService.sendMetric(.errorMetric(action: .error(message: errorMessage),
                                                         category: .registration,
                                                         context: payload.context,
                                                         loginId: loginId,
                                                         errorMessage: errorMessage,
                                                         source: Constants.sourceName))
                }
            } receiveValue: { [unowned self] registerResult in
                eventService.sendMetric(.trackMetric(action: .loggedIn,
                                                     category: .login,
                                                     context: payload.context,
                                                     loginId: loginId,
                                                     authType: payload.authType,
                                                     source: Constants.sourceName))
                state = .ownidCreated
                resultPublisher.send(.success(.userRegisteredAndLoggedIn(registrationResult: registerResult.operationResult, authType: registerResult.authType)))
                resetDataAndState(isResettingToInitialState: false)
            }
            .store(in: &bag)
    }
    
    func handle(_ error: OwnID.CoreSDK.CoreErrorLogWrapper) {
        resetToInitialState()
        resultPublisher.send(.failure(error.error))
    }
}
