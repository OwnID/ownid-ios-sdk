import Foundation
import UIKit
import Combine
import AuthenticationServices

extension OwnID.CoreSDK.BrowserOpenerViewModel {
    struct State {
    }
    
    enum Action {
        case viewCancelled
    }
}

extension OwnID.CoreSDK {
    final class BrowserOpenerViewModel: ObservableObject {
        private var store: Store<State, Action>
        private let authSessionContext = ASWebAuthenticationPresentationContext()
        private var cancellableSession: ASWebAuthenticationSession?
        
        init(store: Store<State, Action>, url: URL, redirectionURL: RedirectionURLString) {
            self.store = store
            startAuthSession(url: url, redirectionURL: redirectionURL)
        }
        
        func cancel() {
            cancellableSession?.cancel()
        }
        
        private func startAuthSession(url: URL, redirectionURL: RedirectionURLString) {
            if let schemeURL = URL(string: redirectionURL) {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: .none)
                { [weak self] _, error in
                    if let errorAuth = error as? ASWebAuthenticationSessionError,
                       case .canceledLogin = errorAuth.code {
                        self?.store.send(.viewCancelled)
                    } else {
                        OwnID.CoreSDK.logger.log(level: .debug, message: "Session finish", type: Self.self)
                        OwnID.CoreSDK.shared.handle(url: schemeURL)
                    }
                }
                cancellableSession = session
                session.presentationContextProvider = authSessionContext
                session.start()
                OwnID.CoreSDK.logger.log(level: .debug, message: "Session start", type: Self.self)
            } else {
                store.send(.viewCancelled)
            }
        }
    }
}
