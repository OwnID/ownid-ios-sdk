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
        private let context: OwnID.CoreSDK.Context
        
        init(store: Store<State, Action>,
             url: URL,
             redirectionURL: RedirectionURLString,
             context: OwnID.CoreSDK.Context) {
            self.store = store
            self.context = context
            startAuthSession(url: url, redirectionURL: redirectionURL)
        }
        
        func cancel() {
            cancellableSession?.cancel()
        }
        
        private func startAuthSession(url: URL, redirectionURL: RedirectionURLString) {
            if URL(string: redirectionURL) != nil {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: .none)
                { [weak self] callbackURL, error in
                    guard let self else { return }
                    if let errorAuth = error as? ASWebAuthenticationSessionError,
                       case .canceledLogin = errorAuth.code {
                        store.send(.viewCancelled)
                    } else {
                        OwnID.CoreSDK.logger.log(level: .debug, message: "Session finish", type: Self.self)
                        OwnID.CoreSDK.shared.handleBrowserCallback(url: callbackURL,
                                                                  error: error,
                                                                  context: context)
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
