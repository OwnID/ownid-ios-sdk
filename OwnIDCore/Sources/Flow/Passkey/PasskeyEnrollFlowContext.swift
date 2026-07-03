import Foundation

internal struct PasskeyEnrollFlowContextKey<Value: Sendable>: Hashable, Sendable {
    internal let rawValue: String

    internal init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Immutable configuration for the passkey enrollment flow.
///
/// Carries the access token, proof token, and reserved headless flag. Built via the ``init(_:)`` closure or ``Builder``.
///
/// Values are per-run inputs. The context does not create an app session, store tokens, or validate token pairing at
/// build time. Missing or unusable values are reported by ``PasskeyEnrollFlow/availability(params:)`` or by the
/// terminal ``PasskeyEnrollFlowFailure`` from ``PasskeyEnrollFlow/start(_:)``.
///
/// If ``proofToken`` is absent, the flow starts passkey attestation before enrollment. If ``proofToken`` is present,
/// the flow starts enrollment directly. When the flow runs attestation itself, the attestation proof token is consumed
/// internally and attestation `ownIdData` is not returned by ``PasskeyEnrollFlowResponse``.
public struct PasskeyEnrollFlowContext: CustomStringConvertible, @unchecked Sendable, CapabilityParams {
    private var storage: [String: Any]

    /// Creates an empty context with no overrides.
    public init() {
        self.storage = [:]
    }

    internal init(storage: [String: Any]) {
        self.storage = storage
    }

    internal subscript<Value: Sendable>(_ key: PasskeyEnrollFlowContextKey<Value>) -> Value? {
        get { storage[key.rawValue] as? Value }
        set { storage[key.rawValue] = newValue }
    }

    /// Returns a builder pre-populated with this context's values for incremental modification.
    public func toBuilder() -> Builder {
        Builder(storage: storage)
    }

    /// DSL builder for ``PasskeyEnrollFlowContext``.
    ///
    /// All properties are optional; unset access token falls back to the current ``Context`` when available.
    public struct Builder: @unchecked Sendable {
        private var storage: [String: Any]

        internal init(storage: [String: Any] = [:]) {
            self.storage = storage
        }

        internal subscript<Value: Sendable>(_ key: PasskeyEnrollFlowContextKey<Value>) -> Value? {
            get { storage[key.rawValue] as? Value }
            set { storage[key.rawValue] = newValue }
        }

        /// Creates a ``PasskeyEnrollFlowContext`` from the builder's current state.
        public func build() -> PasskeyEnrollFlowContext {
            PasskeyEnrollFlowContext(storage: storage)
        }
    }

    /// Creates a context configured via a builder closure.
    ///
    /// - Parameter configure: Closure that sets optional per-run properties on a ``Builder``.
    public init(_ configure: (inout Builder) -> Void) {
        var builder = Builder()
        configure(&builder)
        self = builder.build()
    }

    internal func copy(_ update: (inout Builder) -> Void = { _ in }) -> PasskeyEnrollFlowContext {
        var builder = toBuilder()
        update(&builder)
        return builder.build()
    }

    /// A debug-oriented string that lists configured context keys and values.
    public var description: String {
        let entries = [
            accessToken.map { "accessToken=\($0)" },
            proofToken.map { "proofToken=\($0)" },
            headless.map { "headless=\($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
        return "PasskeyEnrollFlowContext(\(entries))"
    }
}

private enum PasskeyEnrollFlowContextKeys {
    fileprivate static let accessToken = PasskeyEnrollFlowContextKey<AccessToken>("accessToken")
    fileprivate static let proofToken = PasskeyEnrollFlowContextKey<ProofToken>("proofToken")
    fileprivate static let headless = PasskeyEnrollFlowContextKey<Bool>("headless")
    fileprivate static let traceParent = PasskeyEnrollFlowContextKey<String>("traceParent")
}

extension PasskeyEnrollFlowContext {
    /// Access token proving the user is already authenticated.
    ///
    /// When `nil`, the flow falls back to the current ``Context``.
    public var accessToken: AccessToken? {
        get { self[PasskeyEnrollFlowContextKeys.accessToken] }
        set { self[PasskeyEnrollFlowContextKeys.accessToken] = newValue }
    }

    /// Proof token from a prior operation, forwarded to the enrollment API.
    ///
    /// When set, the flow skips local passkey attestation.
    public var proofToken: ProofToken? {
        get { self[PasskeyEnrollFlowContextKeys.proofToken] }
        set { self[PasskeyEnrollFlowContextKeys.proofToken] = newValue }
    }

    /// Reserved for future use and currently has no observable effect.
    ///
    /// This does not suppress platform passkey UI when no proof token is provided.
    public var headless: Bool? {
        get { self[PasskeyEnrollFlowContextKeys.headless] }
        set { self[PasskeyEnrollFlowContextKeys.headless] = newValue }
    }

    internal var traceParent: String? {
        get { self[PasskeyEnrollFlowContextKeys.traceParent] }
        set { self[PasskeyEnrollFlowContextKeys.traceParent] = newValue }
    }
}

extension PasskeyEnrollFlowContext.Builder {
    /// Access token proving the user is already authenticated.
    ///
    /// When `nil`, the flow falls back to the current ``Context``.
    public var accessToken: AccessToken? {
        get { self[PasskeyEnrollFlowContextKeys.accessToken] }
        set { self[PasskeyEnrollFlowContextKeys.accessToken] = newValue }
    }

    /// Proof token from a prior operation.
    ///
    /// When set, the flow skips local passkey attestation.
    public var proofToken: ProofToken? {
        get { self[PasskeyEnrollFlowContextKeys.proofToken] }
        set { self[PasskeyEnrollFlowContextKeys.proofToken] = newValue }
    }

    /// Reserved for future use and currently has no observable effect.
    ///
    /// This does not suppress platform passkey UI when no proof token is provided.
    public var headless: Bool? {
        get { self[PasskeyEnrollFlowContextKeys.headless] }
        set { self[PasskeyEnrollFlowContextKeys.headless] = newValue }
    }

    internal var traceParent: String? {
        get { self[PasskeyEnrollFlowContextKeys.traceParent] }
        set { self[PasskeyEnrollFlowContextKeys.traceParent] = newValue }
    }
}
