import Foundation

public extension OwnID {
    /// Builder class for configuring the OwnID Elite flow.
    ///
    /// This builder allows you to define the events and their corresponding handlers that will be triggered during the OwnID Elite flow.
    class StartBuilder {
        private var providers: OwnID.Providers?
        private var eventWrappers: [any FlowWrapper]?
        
        /// Configures providers using an ``OwnID/ProvidersBuilder``. Optionally, if present will override global providers set in ``OwnID/providers(_:)``.
        /// - Parameter block: A closure that configures providers.
        public func providers(_ block: (ProvidersBuilder) -> Void) {
            let builder = ProvidersBuilder()
            block(builder)
            providers = builder.build()
        }
        
        /// Configures the flow events using an ``OwnID/FlowEventsBuilder``.
        /// - Parameter block: A closure that configures flow events.
        public func events(_ block: (FlowEventsBuilder) -> Void) {
            let builder = FlowEventsBuilder()
            block(builder)
            eventWrappers = builder.build()
        }
        
        /// Builds the ``OwnID/StartBuilder`` instance.
        /// - Returns: The built ``OwnID/StartBuilder`` instance.
        public func build() -> StartBuilder {
            return self
        }
        
        /// Starts the OwnID flow with configured providers and events.
        public func invoke(options: EliteOptions?) {
            OwnID.CoreSDK.start(options: options, providers: providers, eventWrappers: eventWrappers ?? [])
        }
    }
    
    /// Initiates the OwnID Elite authentication flow, allowing for customization through providers and event handlers.
    /// 
    /// OwnID Elite provides a powerful and flexible framework for integrating and customizing authentication processes within your applications. Using **Providers** and **Events**, developers can implement or override specific aspects of the authentication flow, tailoring the user experience to meet the unique needs of their applications.
    /// - **Providers**: Manage critical components such as session handling and authentication mechanisms, including traditional password-based logins. They allow developers to define how users are authenticated, how sessions are maintained, and how accounts are managed within the application. See ``OwnID/Providers``. 
    /// 
    ///   Define providers globally using  ``OwnID/providers(_:)`` and override them for specific flows if required.
    /// 
    /// - **Events**: Handle specific actions and responses within the authentication flow. They allow developers to customize behavior when specific events occur. For example, when the authentication process completes, when an error occurs, or when the flow detects a new user and prompts for registration.
    /// All **Events** and **Provider** handlers are optional and defined as suspend functions.
    /// 
    /// **Note:** To override **Provider** handlers set at the OwnID SDK global level, define them here.
    ///
    /// ```swift
    /// OwnID.start {
    ///     // Optional, if present will override
    ///     // global providers set in OwnID.providers
    ///     $0.providers {
    ///         $0.session {
    ///             $0.create { loginId, session, authToken, authMethod in
    ///             }
    ///       }
    ///         $0.account {
    ///             $0.register { loginId, profile, ownIdData, authToken in
    ///             }
    ///         }
    ///         $0.auth {
    ///             $0.password {
    ///                 $0.authenticate { loginId, password in
    ///                 }
    ///             }
    ///         }
    ///     }
    ///     $0.events {
    ///         $0.onNativeAction { name, params in
    ///         }
    ///         $0.onAccountNotFound { loginId, ownIdData, authToken in
    ///         }
    ///         $0.onFinish { loginId, authMethod, authToken in
    ///         }
    ///         $0.onError { error in
    ///         }
    ///         $0.onClose {
    ///         }
    ///     }
    /// }
    /// ```
    /// 
    /// - Parameter block: A closure that configures the flow using ``OwnID/StartBuilder``.
    static func start(options: EliteOptions? = nil, _ block: (StartBuilder) -> Void) {
        let builder = StartBuilder()
        block(builder)
        builder.build().invoke(options: options)
    }
    
    struct EliteOptions {
        public struct WebView {
            public var baseURL: String?
            public var html: String?
            public var webViewIsInspectable: Bool = false
            
            public init(baseURL: String? = nil, html: String? = nil, webViewIsInspectable: Bool = false) {
                self.baseURL = baseURL
                self.html = html
                self.webViewIsInspectable = webViewIsInspectable
            }
        }
        
        public init(webView: WebView? = nil) {
            self.webView = webView
        }
        
        public var webView: WebView?
    }
}
