import Foundation

internal struct BoostFlowContextKey<Value: Sendable>: Hashable, Sendable {
    internal let rawValue: String

    internal init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Configuration for a Boost authentication flow.
///
/// Carries optional login-ID hints and behavioral flags that customize flow execution. `BoostFlowContext` has value
/// semantics; configure a value before passing it to a flow, or use ``init(_:)`` / ``Builder`` to create a separate
/// value for a run. Use ``empty`` for default behavior.
///
/// Boost uses an available access token before login-ID hints. When an access token is available from the Boost context
/// or current ``Context``, the flow resolves the login ID from that token and continues token-first.
///
/// If no access token is available, login-ID hints use this precedence:
/// - ``loginID`` from this context when set.
/// - Raw input supplied through ``loginID(_:type:)`` when no type is provided.
/// - Typed login ID, then raw login ID, from the current ``Context``.
/// - The stored last user, unless ``ignoreLastUser`` is `true`.
///
/// Typed login IDs are used as concrete identifiers. Raw login IDs are text hints that OwnID can classify later.
///
public struct BoostFlowContext: CustomStringConvertible, @unchecked Sendable {
    /// A context with no flow-context overrides.
    public static let empty = BoostFlowContext()

    private var storage: [String: Any]

    /// Creates an empty context with no flow-context overrides.
    public init() {
        self.storage = [:]
    }

    internal init(storage: [String: Any]) {
        self.storage = storage
    }

    internal subscript<Value: Sendable>(_ key: BoostFlowContextKey<Value>) -> Value? {
        get { storage[key.rawValue] as? Value }
        set { storage[key.rawValue] = newValue }
    }

    /// Returns a builder pre-populated with this context's values for creating another context value.
    public func toBuilder() -> Builder {
        Builder(storage: storage)
    }

    /// DSL builder for ``BoostFlowContext``.
    ///
    /// All properties are optional; unset values use flow defaults and current SDK context values where applicable.
    public struct Builder: @unchecked Sendable {
        private var storage: [String: Any]

        internal init(storage: [String: Any] = [:]) {
            self.storage = storage
        }

        internal subscript<Value: Sendable>(_ key: BoostFlowContextKey<Value>) -> Value? {
            get { storage[key.rawValue] as? Value }
            set { storage[key.rawValue] = newValue }
        }

        /// Creates a ``BoostFlowContext`` from the builder's current state.
        public func build() -> BoostFlowContext {
            BoostFlowContext(storage: storage)
        }
    }

    /// Creates a context configured via a builder closure.
    ///
    /// - Parameter configure: Closure that sets properties on a ``Builder``.
    public init(_ configure: (inout Builder) -> Void) {
        var builder = Builder()
        configure(&builder)
        self = builder.build()
    }

    internal func isTargetScoreAchieved() -> Bool {
        guard let authRequirements = authRequiredResponse?.authRequirements else { return false }
        let succeededScore =
            requestedOps?.filter { $0.value }.keys.reduce(0) { total, succeededType in
                let score = authRequirements.operations.first { $0.type == succeededType }?.score ?? 0
                return total + score
            } ?? 0
        return succeededScore >= authRequirements.targetScore
    }

    internal func getNextOperationType() -> [OperationType]? {
        guard let authRequirements = authRequiredResponse?.authRequirements else { return nil }
        let passedTypes = requestedOps.map { Set($0.keys) } ?? Set()
        let currentLoginID = loginID

        let nextTypes = authRequirements.operations
            .filter { !passedTypes.contains($0.type) }
            .filter { $0.isSelectableBoostAuthOperation(loginID: currentLoginID) }
            .map { $0.type }

        return nextTypes.isEmpty ? nil : nextTypes
    }

    internal mutating func addSucceedOperation(operationType: OperationType) {
        var currentOps = requestedOps ?? [:]
        if currentOps[operationType] == nil {
            currentOps[operationType] = true
            requestedOps = currentOps
        }
    }

    internal mutating func addFailedOperation(operationType: OperationType) {
        var currentOps = requestedOps ?? [:]
        if currentOps[operationType] == nil {
            currentOps[operationType] = false
            requestedOps = currentOps
        }
    }

    /// A debug-oriented string that summarizes configured fields and redacts sensitive payloads.
    public var description: String {
        let entries = storage.map { (key, value) -> String in
            if ["ownIdData", "sessionPayload", "rawLoginID"].contains(key) {
                return "\(key)=\(String(describing: value).shorten())"
            } else {
                return "\(key)=\(value)"
            }
        }
        .joined(separator: ", ")
        return "FlowContext(\(entries))"
    }
}

extension OperationRequirement {
    fileprivate func isSelectableBoostAuthOperation(loginID: LoginID?) -> Bool {
        switch type {
        case .passkeyCreation: return true
        case .passkeyAuth: return true
        case .emailVerification: return supports(loginID: loginID, targetType: .email)
        case .phoneNumberVerification: return supports(loginID: loginID, targetType: .phoneNumber)
        default: return false
        }
    }

    private func supports(loginID: LoginID?, targetType: LoginIDType) -> Bool {
        loginID == nil || loginID?.type == targetType || (loginID?.type == .userName && channels?.isEmpty == false)
    }
}

private enum BoostFlowContextKeys {
    fileprivate static let loginID = BoostFlowContextKey<LoginID>("loginID")
    fileprivate static let rawLoginID = BoostFlowContextKey<String>("rawLoginID")
    fileprivate static let accessToken = BoostFlowContextKey<AccessToken>("accessToken")
    fileprivate static let ignoreLastUser = BoostFlowContextKey<Bool>("ignoreLastUser")
    fileprivate static let proofToken = BoostFlowContextKey<ProofToken>("proofToken")
    fileprivate static let ownIdData = BoostFlowContextKey<String>("ownIdData")
    fileprivate static let sessionPayload = BoostFlowContextKey<String>("sessionPayload")
    fileprivate static let authMethod = BoostFlowContextKey<AuthMethod>("authMethod")
    fileprivate static let authRequiredResponse = BoostFlowContextKey<LoginResponse.AuthRequired>("authRequiredResponse")
    fileprivate static let requestedOps = BoostFlowContextKey<[OperationType: Bool]>("requestedOps")
    fileprivate static let source = BoostFlowContextKey<FlowInfo.Source>("source")
    fileprivate static let traceParent = BoostFlowContextKey<String>("traceParent")
}

extension BoostFlowContext {
    /// Typed login identifier hint for the flow.
    ///
    /// Set this when the app already knows both the user's identifier and type. When this value is `nil`, no access
    /// token is available, and no raw login ID was supplied, the flow may use the current ``Context`` login ID or the
    /// stored last user when ``ignoreLastUser`` is not `true`.
    public var loginID: LoginID? {
        get { self[BoostFlowContextKeys.loginID] }
        set {
            self[BoostFlowContextKeys.loginID] = newValue
            if newValue != nil {
                self[BoostFlowContextKeys.rawLoginID] = nil
            }
        }
    }

    /// Sets a login ID using either typed or raw input.
    ///
    /// Pass `type` when the app knows whether the value is an email, phone number, or username. Leave `type` `nil`
    /// when the app only has the text value and wants OwnID to classify it later. A typed value takes precedence over
    /// a raw value. Calling this function clears any previously assigned ``loginID`` when `type` is `nil`, and clears
    /// the raw value when `type` is provided.
    public mutating func loginID(_ id: String, type: LoginIDType? = nil) {
        if let type {
            loginID = LoginID(id: id, type: type)
        } else {
            loginID = nil
            rawLoginID = id
        }
    }

    /// When `true`, ignores the stored last user.
    ///
    /// Explicit values supplied through ``loginID`` or ``loginID(_:type:)``, and values from the current ``Context``,
    /// can still pre-fill login-ID collection. Access-token inputs still take precedence over login-ID hints.
    public var ignoreLastUser: Bool? {
        get { self[BoostFlowContextKeys.ignoreLastUser] }
        set { self[BoostFlowContextKeys.ignoreLastUser] = newValue }
    }

    internal var source: FlowInfo.Source? {
        get { self[BoostFlowContextKeys.source] }
        set { self[BoostFlowContextKeys.source] = newValue }
    }

    internal var traceParent: String? {
        get { self[BoostFlowContextKeys.traceParent] }
        set { self[BoostFlowContextKeys.traceParent] = newValue }
    }

    internal var accessToken: AccessToken? {
        get { self[BoostFlowContextKeys.accessToken] }
        set { self[BoostFlowContextKeys.accessToken] = newValue }
    }

    internal var proofToken: ProofToken? {
        get { self[BoostFlowContextKeys.proofToken] }
        set { self[BoostFlowContextKeys.proofToken] = newValue }
    }

    internal var rawLoginID: String? {
        get { self[BoostFlowContextKeys.rawLoginID] }
        set { self[BoostFlowContextKeys.rawLoginID] = newValue }
    }

    internal var ownIdData: String? {
        get { self[BoostFlowContextKeys.ownIdData] }
        set { self[BoostFlowContextKeys.ownIdData] = newValue }
    }

    internal var sessionPayload: String? {
        get { self[BoostFlowContextKeys.sessionPayload] }
        set { self[BoostFlowContextKeys.sessionPayload] = newValue }
    }

    internal var authMethod: AuthMethod? {
        get { self[BoostFlowContextKeys.authMethod] }
        set { self[BoostFlowContextKeys.authMethod] = newValue }
    }

    internal var authRequiredResponse: LoginResponse.AuthRequired? {
        get { self[BoostFlowContextKeys.authRequiredResponse] }
        set { self[BoostFlowContextKeys.authRequiredResponse] = newValue }
    }

    internal var requestedOps: [OperationType: Bool]? {
        get { self[BoostFlowContextKeys.requestedOps] }
        set { self[BoostFlowContextKeys.requestedOps] = newValue }
    }
}

extension BoostFlowContext.Builder {
    /// Typed login identifier hint for the flow.
    ///
    /// Set this when the app already knows both the user's identifier and type. Assigning a non-`nil` value clears any
    /// raw login-ID hint previously supplied through ``loginID(_:type:)``.
    public var loginID: LoginID? {
        get { self[BoostFlowContextKeys.loginID] }
        set {
            self[BoostFlowContextKeys.loginID] = newValue
            if newValue != nil {
                self[BoostFlowContextKeys.rawLoginID] = nil
            }
        }
    }

    /// Sets a login ID using either typed or raw input.
    ///
    /// Pass `type` when the app knows whether the value is an email, phone number, or username. Leave `type` `nil`
    /// when the app only has the text value and wants OwnID to classify it later. A typed value takes precedence over
    /// a raw value. Calling this function clears any previously assigned ``loginID`` when `type` is `nil`, and clears
    /// the raw value when `type` is provided.
    public mutating func loginID(_ id: String, type: LoginIDType? = nil) {
        if let type {
            loginID = LoginID(id: id, type: type)
        } else {
            loginID = nil
            rawLoginID = id
        }
    }

    /// When `true`, ignores the stored last user.
    ///
    /// Explicit values supplied through ``loginID`` or ``loginID(_:type:)``, and values from the current ``Context``,
    /// can still pre-fill login-ID collection. Access-token inputs still take precedence over login-ID hints.
    public var ignoreLastUser: Bool? {
        get { self[BoostFlowContextKeys.ignoreLastUser] }
        set { self[BoostFlowContextKeys.ignoreLastUser] = newValue }
    }

    /// Internal source label for flow-level telemetry.
    ///
    /// Intended for SDK-owned integrations. Leave `nil` to use the default explicit source.
    @_spi(OwnIDInternal) public var source: FlowInfo.Source? {
        get { self[BoostFlowContextKeys.source] }
        set { self[BoostFlowContextKeys.source] = newValue }
    }

    internal var traceParent: String? {
        get { self[BoostFlowContextKeys.traceParent] }
        set { self[BoostFlowContextKeys.traceParent] = newValue }
    }

    internal var accessToken: AccessToken? {
        get { self[BoostFlowContextKeys.accessToken] }
        set { self[BoostFlowContextKeys.accessToken] = newValue }
    }

    internal var proofToken: ProofToken? {
        get { self[BoostFlowContextKeys.proofToken] }
        set { self[BoostFlowContextKeys.proofToken] = newValue }
    }

    internal var rawLoginID: String? {
        get { self[BoostFlowContextKeys.rawLoginID] }
        set { self[BoostFlowContextKeys.rawLoginID] = newValue }
    }

    internal var ownIdData: String? {
        get { self[BoostFlowContextKeys.ownIdData] }
        set { self[BoostFlowContextKeys.ownIdData] = newValue }
    }

    internal var sessionPayload: String? {
        get { self[BoostFlowContextKeys.sessionPayload] }
        set { self[BoostFlowContextKeys.sessionPayload] = newValue }
    }

    internal var authMethod: AuthMethod? {
        get { self[BoostFlowContextKeys.authMethod] }
        set { self[BoostFlowContextKeys.authMethod] = newValue }
    }

    internal var authRequiredResponse: LoginResponse.AuthRequired? {
        get { self[BoostFlowContextKeys.authRequiredResponse] }
        set { self[BoostFlowContextKeys.authRequiredResponse] = newValue }
    }

    internal var requestedOps: [OperationType: Bool]? {
        get { self[BoostFlowContextKeys.requestedOps] }
        set { self[BoostFlowContextKeys.requestedOps] = newValue }
    }
}
