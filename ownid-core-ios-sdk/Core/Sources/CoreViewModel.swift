import Foundation
import Combine

extension OwnID.CoreSDK.ViewModelAction: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .addToState:
            return "addToState"
        case .sendInitialRequest:
            return "sendInitialRequest"
        case .initialRequestLoaded:
            return "initialRequestLoaded"
        case .browserURLCreated:
            return "browserURLCreated"
        case .error(let error):
            return "error \(error.localizedDescription)"
        case .sendStatusRequest:
            return "sendStatusRequest"
        case .browserCancelled:
            return "browserCancelled"
        case .statusRequestLoaded:
            return "statusRequestLoaded"
        case .browserVM:
            return "browserVM"
        }
    }
}
extension OwnID.CoreSDK {
    enum ViewModelAction {
        case addToState(browserViewModelStore: Store<BrowserOpenerViewModel.State, BrowserOpenerViewModel.Action>)
        case sendInitialRequest
        case initialRequestLoaded(response: OwnID.CoreSDK.Init.Response)
        case browserURLCreated(URL)
        case error(OwnID.CoreSDK.Error)
        case sendStatusRequest
        case browserCancelled
        case statusRequestLoaded(response: OwnID.CoreSDK.Payload)
        case browserVM(BrowserOpenerViewModel.Action)
        
        var browserVM: BrowserOpenerViewModel.Action? {
            get {
                guard case let .browserVM(value) = self else { return nil }
                return value
            }
            set {
                guard case .browserVM = self, let newValue = newValue else { return }
                self = .browserVM(newValue)
            }
        }
    }
    
    struct ViewModelState: LoggingEnabled {
#warning("Make this property controlled from the SDK reducers or remove it")
        let isLoggingEnabled = false
        
        let sdkConfigurationName: String
        let session: APISessionProtocol
        let email: OwnID.CoreSDK.Email?
        let token: OwnID.CoreSDK.JWTToken?
        let type: OwnID.CoreSDK.RequestType
        let browserViewModelInitializer: ((Store<OwnID.CoreSDK.BrowserOpenerViewModel.State, OwnID.CoreSDK.BrowserOpenerViewModel.Action>, URL) -> BrowserOpener)
        var browserViewModelStore: Store<BrowserOpenerViewModel.State, BrowserOpenerViewModel.Action>!
        var browserViewModel: BrowserOpener?
        
        var browserViewModelState: BrowserOpenerViewModel.State {
            get { sdkConfigurationName }
            set { }
        }
    }
    
    static func viewModelReducer(state: inout ViewModelState, action: ViewModelAction) -> [Effect<ViewModelAction>] {
        switch action {
        case .sendInitialRequest:
            if let email = state.email, !email.rawValue.isEmpty, !email.isValid {
                return errorEffect(.emailIsInvalid)
            }
            return [sendInitialRequest(type: state.type, token: state.token, session: state.session)]
            
        case let .initialRequestLoaded(response):
            guard let context = response.context else { return errorEffect(.contextIsMissing) }
            let browserAffect = browserURLEffect(for: context,
                                                 browserURL: response.url,
                                                 email: state.email,
                                                 sdkConfigurationName: state.sdkConfigurationName)
            return [browserAffect]
            
        case .error:
            return []
            
        case let .browserURLCreated(url):
            let vm = state.browserViewModelInitializer(state.browserViewModelStore, url)
            state.browserViewModel = vm
            return []
            
        case .sendStatusRequest:
            state.browserViewModel = .none
            return [sendStatusRequest(session: state.session)]
            
        case .browserCancelled:
            state.browserViewModel = .none
            return []
            
        case .statusRequestLoaded:
            return []
            
        case let .addToState(browserViewModelStore):
            state.browserViewModelStore = browserViewModelStore
            return []
            
        case let .browserVM(browserVMAction):
            switch browserVMAction {
            case .viewCancelled:
                return [Just(.browserCancelled).eraseToEffect()]
            }
        }
    }
    
    static func browserURLEffect(for context: String,
                                 browserURL: String,
                                 email: Email?,
                                 sdkConfigurationName: String) -> Effect<ViewModelAction> {
        Effect<ViewModelAction>.sync {
            let redirectionEncoded = OwnID.CoreSDK.shared.getConfiguration(for: sdkConfigurationName)
                .redirectionURL
                .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            let redirect = redirectionEncoded! + "?context=" + context
            let redirectParameter = "&redirectURI=" + redirect
            var urlString = browserURL
            if let email = email {
                var emailSet = CharacterSet.urlHostAllowed
                emailSet.remove("+")
                if let encoded = email.rawValue.addingPercentEncoding(withAllowedCharacters: emailSet) {
                    let emailParameter = "&e=" + encoded
                    urlString.append(emailParameter)
                }
            }
            urlString.append(redirectParameter)
            return .browserURLCreated(URL(string: urlString)!)
        }
    }
    
    static func errorEffect(_ error: OwnID.CoreSDK.Error) -> [Effect<ViewModelAction>] {
        [Just(.error(error)).eraseToEffect()]
    }
    
    static func sendInitialRequest(type: OwnID.CoreSDK.RequestType,
                                   token: OwnID.CoreSDK.JWTToken?,
                                   session: APISessionProtocol) -> Effect<ViewModelAction> {
        session.performInitRequest(type: type, token: token)
            .receive(on: DispatchQueue.main)
            .map { ViewModelAction.initialRequestLoaded(response: $0) }
            .catch { Just(ViewModelAction.error($0)) }
            .eraseToEffect()
    }
    
    static func sendStatusRequest(session: APISessionProtocol) -> Effect<ViewModelAction> {
        session.performStatusRequest()
            .map { ViewModelAction.statusRequestLoaded(response: $0) }
            .catch { Just(ViewModelAction.error($0)) }
            .eraseToEffect()
    }
}

extension OwnID.CoreSDK {
    public final class CoreViewModel: ObservableObject {
        @Published var store: Store<OwnID.CoreSDK.ViewModelState, OwnID.CoreSDK.ViewModelAction>
        private let resultPublisher = PassthroughSubject<OwnID.CoreSDK.Event, OwnID.CoreSDK.Error>()
        private var bag = Set<AnyCancellable>()
        
        public var eventPublisher: OwnID.CoreSDK.EventPublisher { resultPublisher.receive(on: DispatchQueue.main).eraseToAnyPublisher() }
        
        init(type: OwnID.CoreSDK.RequestType,
             email: OwnID.CoreSDK.Email?,
             token: OwnID.CoreSDK.JWTToken?,
             session: APISessionProtocol,
             sdkConfigurationName: String,
             browserViewModelInitializer: @escaping ((Store<OwnID.CoreSDK.BrowserOpenerViewModel.State, OwnID.CoreSDK.BrowserOpenerViewModel.Action>, URL) -> BrowserOpener) = { (store, url) -> BrowserOpener in return BrowserOpenerViewModel(store: store, url: url) }) {
            let initialState = OwnID.CoreSDK.ViewModelState(sdkConfigurationName: sdkConfigurationName,
                                                            session: session,
                                                            email: email,
                                                            token: token,
                                                            type: type,
                                                            browserViewModelInitializer: browserViewModelInitializer)
            let store = Store(
                initialValue: initialState,
                reducer: with(
                    OwnID.CoreSDK.viewModelReducer,
                    logging
                )
            )
            self.store = store
            let browserStore = self.store.view(value: { $0.sdkConfigurationName} , action: { .browserVM($0) })
            self.store.send(.addToState(browserViewModelStore: browserStore))
            setupEventPublisher()
        }
        
        public func start() {
            store.send(.sendInitialRequest)
        }
        
        func subscribeToURL(publisher: AnyPublisher<Void, OwnID.CoreSDK.Error>) {
            publisher
                .sink { [unowned self] completion in
                    if case .failure(let error) = completion {
                        store.send(.error(error))
                    }
                } receiveValue: { [unowned self] url in
                    store.send(.sendStatusRequest)
                }
                .store(in: &bag)
        }
        
        private var internalStatesChange = [String]()
        
        private func logInternalStates() {
            OwnID.CoreSDK.logger.logCore(.entry(message: "\(internalStatesChange)", Self.self))
            internalStatesChange.removeAll()
        }
        
        private func setupEventPublisher() {
            store
                .actionsPublisher
                .sink { [unowned self] action in
                    switch action {
                    case .sendInitialRequest:
                        internalStatesChange.append(String(describing: action))
                        resultPublisher.send(.loading)
                        
                    case .initialRequestLoaded,
                            .browserURLCreated,
                            .sendStatusRequest,
                            .addToState,
                            .browserVM:
                        internalStatesChange.append(String(describing: action))
                        
                    case let .statusRequestLoaded(payload):
                        internalStatesChange.append(String(describing: action))
                        flowsFinished()
                        resultPublisher.send(.success(payload))
                        
                    case .error(let error):
                        internalStatesChange.append(String(describing: action))
                        flowsFinished()
                        resultPublisher.send(completion: .failure(error))
                        
                    case .browserCancelled:
                        internalStatesChange.append(String(describing: action))
                        flowsFinished()
                        resultPublisher.send(.cancelled)
                    }
                }
                .store(in: &bag)
        }
        
        private func flowsFinished() {
            logInternalStates()
            bag.removeAll()
        }
    }
}
