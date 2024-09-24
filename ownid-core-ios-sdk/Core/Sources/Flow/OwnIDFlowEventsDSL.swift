import Foundation

extension OwnID {
    ///  Builder class for defining the handlers for different events in the OwnID Elite flow.
    public class FlowEventsBuilder {
        private var onFinish: ((_ loginId: String, _ authMethod: OwnID.CoreSDK.AuthMethod?, _ authToken: String?) async -> Void)?
        private var onError: ((_ error: OwnID.CoreSDK.Error) async -> Void)?
        private var onClose: (() async -> Void)?
        
        /// Sets the handler for the `onFinish` event.
        ///
        /// The `onFinish` event is triggered when the authentication flow is successfully completed.
        /// This event allows you to define actions that should be taken once the user is authenticated.
        ///
        /// **Note:** This is a terminal event. No other handlers will be called after this one.
        /// - Parameter block: The closure to be executed upon completion. It receives **loginId**, **authMethod**, **authToken** parameters.
        public func onFinish(_ block: @escaping (_ loginId: String, _ authMethod: OwnID.CoreSDK.AuthMethod?, _ authToken: String?) async -> Void) {
            self.onFinish = block
        }
        
        /// Sets the handler for the `onError` event.
        ///
        /// The `onError` event is triggered when an error occurs during the authentication flow.
        /// This event allows developers to handle errors gracefully, such as by logging them or displaying error messages to the user.
        ///
        /// **Note:** This is a terminal event. No other handlers will be called after this one.
        /// - Parameter block: The closure to be executed upon completion. It receives **error** parameter.
        public func onError(_ block: @escaping (_ error: OwnID.CoreSDK.Error) async -> Void) {
            self.onError = block
        }
        
        /// Sets the handler for the `onClose` event.
        ///
        /// The `onClose` event is triggered when the authentication flow is closed, either by user action or automatically. This event allows developers to define what should happen when the authentication flow is interrupted or completed without a successful login.
        ///
        /// **Note:** This is a terminal event. No other handlers will be called after this one.
        /// - Parameter block: The closure to be executed upon completion.
        public func onClose(_ block: @escaping () async -> Void) {
            self.onClose = block
        }
        
        /// Builds a list of ``FlowWrapper`` based on the configured event handlers.
        /// - Returns: A list of ``FlowWrapper`` instances.
        public func build() -> [any FlowWrapper] {
            var wrappers: [any FlowWrapper] = []
            if let onFinish = onFinish {
                wrappers.append(OwnID.OnFinishWrapper(onFinish: onFinish))
            }
            if let onError = onError {
                wrappers.append(OwnID.OnErrorWrapper(onError: onError))
            }
            if let onClose = onClose {
                wrappers.append(OwnID.OnCloseWrapper(onClose: onClose))
            }
            return wrappers
        }
    }
}
