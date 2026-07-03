import Foundation

/// OwnID authentication flow namespace.
///
/// Use this namespace for the highest-level OwnID integrations.
///
/// Namespace handles are bound to the SDK scope they were obtained from.
/// After ``OwnID/destroy(instanceName:)`` or same-name reinitialization, previously returned namespace handles are
/// invalid and should be reacquired from ``OwnID/flows`` or the current ``OwnIDInstance``.
///
/// These flows orchestrate multiple operations for you based on the current context and server requirements. Passing
/// `nil`, or using the zero-argument ``FlowEntry/start()`` overload, starts Boost and Elite with their empty flow
/// contexts.
///
/// Use ``withContext(_:_:)`` to scope flows with a login ID or access token and ``withProviders(_:_:)`` to register
/// providers. Use ``FlowEntry/start(_:)`` to launch the selected flow.
/// Namespace entry properties do not resolve their underlying flow runtime until ``FlowEntry/start(_:)`` is called.
/// Each start call returns a caller-owned flow controller; keep it while the flow is active and use it to await the
/// terminal flow result.
///
/// Accessed via ``OwnID/flows`` (default instance) or ``OwnIDInstance/flows``.
public struct OwnIDFlows: Sendable, OwnIDNamespace {
    internal let container: any DIContainer

    public let boost: Boost

    /// Web-based authentication flow using a web view and WebBridge.
    public let elite: FlowEntry<EliteFlowContext?, any EliteFlowController>

    internal init(container: any DIContainer) {
        self.container = container
        self.boost = Boost(container: container)
        self.elite = flowEntry(
            container: container,
            runtimeType: (any EliteFlow).self,
            start: { runtime, context in runtime.start(context ?? .empty) }
        )
    }
}

extension OwnIDFlows: OwnIDNamespaceSupport {}

extension OwnIDFlows {
    internal func rebind(container: any DIContainer) -> OwnIDFlows {
        OwnIDFlows(container: container)
    }
}

extension OwnIDFlows {
    /// Boost authentication flow group.
    ///
    /// Use ``login`` for sign-in screens and ``createPasskey`` when account creation should include the OwnID
    /// create-passkey path. The create-passkey flow can end with either an existing-account login or a create-passkey
    /// result.
    public struct Boost: Sendable {
        /// Runs the Boost login flow.
        public let login: FlowEntry<BoostFlowContext?, any BoostLoginFlowController>

        /// Composite account-creation create-passkey flow that can also return an existing-account login result.
        public let createPasskey: FlowEntry<BoostFlowContext?, any BoostCreatePasskeyFlowController>

        fileprivate init(container: any DIContainer) {
            self.login = flowEntry(
                container: container,
                runtimeType: (any BoostLoginFlow).self,
                start: { runtime, context in runtime.start(context ?? .empty) }
            )
            self.createPasskey = flowEntry(
                container: container,
                runtimeType: (any BoostCreatePasskeyFlow).self,
                start: { runtime, context in runtime.start(context ?? .empty) }
            )
        }
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    internal var flowsNamespace: OwnIDFlows {
        OwnIDFlows(container: self)
    }
}
