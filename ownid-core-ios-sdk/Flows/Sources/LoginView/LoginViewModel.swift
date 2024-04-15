import Foundation
import Combine

extension OwnID.FlowsSDK.LoginView.ViewModel {
    enum State {
        case initial
        case coreVM
        case loggedIn
    }
}

public extension OwnID.FlowsSDK.LoginView {
     final class ViewModel: ObservableObject {
        @Published private(set) var state = State.initial
        @Published public var shouldShowTooltip = true
        
        private var bag = Set<AnyCancellable>()
        private var coreViewModelBag = Set<AnyCancellable>()
        private let resultPublisher = PassthroughSubject<Result<OwnID.FlowsSDK.LoginEvent, OwnID.CoreSDK.Error>, Never>()
        private let loginPerformer: LoginPerformer
        private var payload: OwnID.CoreSDK.Payload?
        private let loginType: OwnID.CoreSDK.LoginType
        var coreViewModel: OwnID.CoreSDK.CoreViewModel!
        
        let sdkConfigurationName: String
        let webLanguages: OwnID.CoreSDK.Languages
        public var getEmail: (() -> String)!
        
        public var eventPublisher: OwnID.FlowsSDK.LoginPublisher {
            resultPublisher.eraseToAnyPublisher()
        }
        
        public init(loginPerformer: LoginPerformer,
                    sdkConfigurationName: String,
                    loginType: OwnID.CoreSDK.LoginType = .standard,
                    webLanguages: OwnID.CoreSDK.Languages) {
            OwnID.CoreSDK.logger.logAnalytic(.loginTrackMetric(action: "OwnID Widget is Loaded", context: payload?.context))
            self.sdkConfigurationName = sdkConfigurationName
            self.loginPerformer = loginPerformer
            self.loginType = loginType
            self.webLanguages = webLanguages
        }
        
        /// Reset visual state and any possible data from web flow
        public func resetDataAndState() {
            payload = .none
            resetState()
        }
        
        /// Reset visual state
        public func resetState() {
            coreViewModelBag.removeAll()
            coreViewModel = .none
            state = .initial
        }
        
        func skipPasswordTapped(usersEmail: String) {
            if state == .coreVM {
                return
            }
            
            let email = OwnID.CoreSDK.Email(rawValue: usersEmail)
            let coreViewModel = OwnID.CoreSDK.shared.createCoreViewModelForLogIn(email: email,
                                                                                 loginType: loginType,
                                                                                 sdkConfigurationName: sdkConfigurationName,
                                                                                 webLanguages: webLanguages)
            self.coreViewModel = coreViewModel
            subscribe(to: coreViewModel.eventPublisher)
            state = .coreVM
            
            /// On iOS 13, this `asyncAfter` is required to make sure that subscription created by the time events start to
            /// be passed to publiser.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                coreViewModel.start()
            }
        }
        
        func subscribe(to eventsPublisher: OwnID.CoreSDK.EventPublisher) {
            eventsPublisher
                .sink { [unowned self] completion in
                    if case .failure(let error) = completion {
                        handle(error, context: payload?.context)
                    }
                } receiveValue: { [unowned self] event in
                    switch event {
                    case .success(let payload):
                        process(payload: payload)
                        
                    case .cancelled:
                        handle(.flowCancelled, context: payload?.context)
                        
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
                    OwnID.CoreSDK.logger.logAnalytic(.loginClickMetric(action: "Clicked Skip Password", context: payload?.context))
                        skipPasswordTapped(usersEmail: getEmail())
                }
                .store(in: &bag)
        }
    }
}

private extension OwnID.FlowsSDK.LoginView.ViewModel {
    func process(payload: OwnID.CoreSDK.Payload) {
        self.payload = payload
        let loginPerformerPublisher = loginPerformer.login(payload: payload, email: getEmail())
        loginPerformerPublisher
            .sink { [unowned self] completion in
                if case .failure(let error) = completion {
                    OwnID.CoreSDK.logger.logAnalytic(.loginTrackMetric(action: "User is Logged in", context: payload.context, authType: payload.authType))
                    handle(error, context: payload.context)
                }
            } receiveValue: { [unowned self] loginResult in
                OwnID.CoreSDK.logger.logAnalytic(.loginTrackMetric(action: "User is Logged in", context: payload.context, authType: payload.authType))
                state = .loggedIn
                resultPublisher.send(.success(.loggedIn(loginResult: loginResult.operationResult, authType: loginResult.authType)))
                resetDataAndState()
            }
            .store(in: &bag)
    }
    
    func handle(_ error: OwnID.CoreSDK.Error, context: OwnID.CoreSDK.Context?) {
        switch error {
        case .flowCancelled:
            OwnID.CoreSDK.logger.logAnalytic(.loginTrackMetric(action: "User canceled OwnID flow", context: context))
        case .serverError(let serverError):
            OwnID.CoreSDK.logger.logAnalytic(.loginTrackMetric(action: serverError.error, context: context))
        case .plugin(let error):
            OwnID.CoreSDK.logger.logCore(.entry(level: .warning, message: "Login: \(error.localizedDescription)", Self.self))
        default:
            break
        }
        
        resetDataAndState()
        
        resultPublisher.send(.failure(error))
    }
}
