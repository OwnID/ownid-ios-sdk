import Foundation

extension OwnID {
    ///  Builder class for defining the handlers for different events in the OwnID Elite flow.
    public class FlowEventsBuilder {
        private var onNativeAction: ((_ name: String, _ params: [String: Any]?) async -> Void)?
        private var onAccountNotFound: ((_ loginId: String, _ ownIdData: [String: Any]?, _ authToken: String?) async -> PageAction)?
        private var onFinish: ((_ loginId: String, _ authMethod: OwnID.CoreSDK.AuthMethod?, _ authToken: String?) async -> Void)?
        private var onError: ((_ error: OwnID.CoreSDK.Error) async -> Void)?
        private var onClose: (() async -> Void)?
        
        /// Sets the handler for the `onNativeAction` event.
        ///
        /// This event is triggered when a native action is requested by other event handlers, such as `onAccountNotFound`.
        ///
        /// **Note:** This is a terminal event. No other handlers will be called after this one.
        /// - Parameter block: The closure to be executed upon completion. It receives **name** of the native action, and optional **params** parameters.
        public func onNativeAction(_ block: @escaping (_ name: String, _ params: [String: Any]?) async -> Void) {
            self.onNativeAction = block
        }
        
        /// Sets the handler for the `onAccountNotFound` event.
        ///
        /// The `onAccountNotFound` event is triggered when the provided account details do not match any existing accounts.
        /// This event allows you to handle scenarios where a user needs to be registered or redirected to a registration screen.
        ///
        /// **Use `onAccountNotFound` to customize the Elite flow when an account is not found.**
        ///
        /// - Parameter block: The closure to be executed upon completion. It receives **loginId**, **ownIdData**, **authToken** parameters. It should return a [PageAction] to define the next steps in the flow.
        public func onAccountNotFound(_ block: @escaping (_ loginId: String, _ ownIdData: [String: Any]?, _ authToken: String?) async -> PageAction) {
            self.onAccountNotFound = block
        }
        
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
            if let onNativeAction = onNativeAction {
                wrappers.append(OwnID.OnNativeActionWrapper(onNativeAction: onNativeAction))
            }
            if let onAccountNotFound = onAccountNotFound {
                wrappers.append(OwnID.OnAccountNotFoundWrapper(onAccountNotFound: onAccountNotFound))
            }
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
