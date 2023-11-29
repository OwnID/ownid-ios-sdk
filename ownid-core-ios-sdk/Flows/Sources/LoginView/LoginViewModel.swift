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
        private enum Constants {
            static let sourceName = "OwnIdLoginViewModel"
        }
        
        @Published private(set) var state = State.initial
        @Published public var shouldShowTooltip = true
        
        private var bag = Set<AnyCancellable>()
        private var coreViewModelBag = Set<AnyCancellable>()
        private let resultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.LoginEvent, OwnID.CoreSDK.Error>, Never>()
        private let loginPerformer: LoginPerformer
        private var payload: OwnID.CoreSDK.Payload?
        private var loginId = ""
        var coreViewModel: OwnID.CoreSDK.CoreViewModel!
        var currentMetadata: OwnID.CoreSDK.CurrentMetricInformation?
        let eventService: EventProtocol
        
        let sdkConfigurationName: String
        
        public var eventPublisher: OwnID.LoginPublisher {
            resultPublisher.eraseToAnyPublisher()
        }
        
        public init(loginPerformer: LoginPerformer,
                    sdkConfigurationName: String,
                    loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher,
                    eventService: EventProtocol = OwnID.CoreSDK.eventService) {
            self.sdkConfigurationName = sdkConfigurationName
            self.loginPerformer = loginPerformer
            self.eventService = eventService
            updateLoginIdPublisher(loginIdPublisher)
            Task {
                // Delay the task by 1 second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                sendMetric()
            }
        }
        
        private func sendMetric() {
            if let currentMetadata {
                OwnID.CoreSDK.shared.currentMetricInformation = currentMetadata
            }
            eventService.sendMetric(.trackMetric(action: .loaded,
                                                 category: .login,
                                                 context: payload?.context,
                                                 loginId: loginId,
                                                 source: Constants.sourceName))
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
                    let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForLogIn(loginId: loginId, sdkConfigurationName: sdkConfigurationName)
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
                        handle(error)
                        OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .error(message: error.localizedDescription),
                                                                           category: .login,
                                                                           context: OwnID.CoreSDK.logger.context,
                                                                           errorMessage: error.localizedDescription))
                    }
                } receiveValue: { [unowned self] event in
                    switch event {
                    case .success(let payload):
                        process(payload: payload)
                        
                    case .cancelled(let flow):
                        let error = OwnID.CoreSDK.Error.flowCancelled(flow: flow)
                        handle(.coreLog(error: error, type: Self.self))
                        OwnID.CoreSDK.eventService.sendMetric(.errorMetric(action: .error(message: error.localizedDescription),
                                                                           category: .login,
                                                                           context: OwnID.CoreSDK.logger.context,
                                                                           errorMessage: error.localizedDescription))
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
                } receiveValue: { [unowned self] event in
                    if state == .initial {
                        eventService.sendMetric(.clickMetric(action: .click,
                                                             category: .login,
                                                             context: payload?.context,
                                                             hasLoginId: !loginId.isEmpty,
                                                             source: Constants.sourceName))
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
        let loginPerformerPublisher = loginPerformer.login(payload: payload, loginId: loginId)
        loginPerformerPublisher
            .sink { [unowned self] completion in
                if case .failure(let error) = completion {
                    handle(error)
                    let errorMessage = error.error.localizedDescription
                    eventService.sendMetric(.errorMetric(action: .error(message: errorMessage),
                                                         category: .login,
                                                         context: payload.context,
                                                         errorMessage: errorMessage,
                                                         source: Constants.sourceName))
                }
            } receiveValue: { [unowned self] loginResult in
                eventService.sendMetric(.trackMetric(action: .loggedIn,
                                                     category: .login,
                                                     context: payload.context,
                                                     loginId: loginId,
                                                     authType: payload.authType,
                                                     source: Constants.sourceName))
                if let loginId = payload.loginId {
                    OwnID.CoreSDK.DefaultsLoginIdSaver.save(loginId: loginId)
                }
                resultPublisher.send(.success(.loggedIn(loginResult: loginResult.operationResult, authType: loginResult.authType)))
                resetDataAndState(isResettingToInitialState: false)
            }
            .store(in: &bag)
    }
    
    func handle(_ error: OwnID.CoreSDK.CoreErrorLogWrapper) {
        resetToInitialState()
        resultPublisher.send(.failure(error.error))
    }
}
