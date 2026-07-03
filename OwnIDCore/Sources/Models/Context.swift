import Foundation

internal struct ContextKey<Value: Sendable>: Hashable, Sendable {
    internal let rawValue: String

    internal init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Caller-supplied authorization input stored in ``Context``.
///
/// An ``Authz`` value represents either login-ID authz or access-token authz, never both. Use factory methods to create
/// access-token or login-ID authz values. Access-token authz stores the supplied ``AccessToken`` as-is.
///
/// ``Authz`` has no public coding contract. The SDK may forward selected context fields, including authz, to supported
/// SDK surfaces.
public struct Authz: Sendable {
    internal let wrapper: AuthzWrapper

    private init(wrapper: AuthzWrapper) {
        self.wrapper = wrapper
    }

    /// Creates access-token authz from a raw token string.
    ///
    /// The value is wrapped as ``AccessToken`` without validation or persistence.
    public static func fromToken(_ token: String) -> Authz {
        Authz(wrapper: .fromAccessToken(AccessToken(token: token)))
    }

    /// Creates access-token authz from ``AccessToken``.
    ///
    /// The provided token object is stored as-is without validation or persistence.
    public static func fromToken(_ token: AccessToken) -> Authz {
        Authz(wrapper: .fromAccessToken(token))
    }

    /// Creates login-ID authz from a raw ID string and optional type.
    ///
    /// When `type` is `nil`, the raw value is stored for later resolution by the consuming surface.
    /// When `type` is provided, the typed ``LoginID`` is stored as-is.
    ///
    /// This method does not validate `id`.
    public static func start(_ id: String, type: LoginIDType? = nil) -> Authz {
        if let type {
            return Authz(wrapper: .typedLoginIDAuthz(LoginID(id: id, type: type)))
        }
        return Authz(wrapper: .rawLoginIDAuthz(id))
    }

    /// Creates login-ID authz from typed ``LoginID``.
    ///
    /// The provided value is stored as-is.
    /// Additional type checks or validation depend on the consuming surface.
    public static func start(_ loginID: LoginID) -> Authz {
        Authz(wrapper: .typedLoginIDAuthz(loginID))
    }
}

internal enum AuthzWrapper: Sendable {
    case rawLoginIDAuthz(String)
    case typedLoginIDAuthz(LoginID)
    case fromAccessToken(AccessToken)
}

/// Scoped value of app-supplied context for SDK surfaces.
///
/// Build this with ``Builder`` through ``OwnID/withContext(_:_:)``, ``OwnID/setContext(_:)``, or the equivalent
/// instance/namespace APIs.
///
/// Raw login-ID authz may be resolved later by the consuming surface.
/// Typed ``LoginID`` authz is preserved as provided.
/// Exact type requirements and validation behavior depend on the consuming surface.
///
/// ``Context`` itself has no public coding contract. Consuming SDK surfaces serialize only the payload fields they
/// support.
///
/// Treat context values as scoped inputs, not durable storage. The SDK keeps them in the active context scope until that
/// scope is cleared, replaced, or discarded, and callers remain responsible for handling identifiers and tokens as
/// sensitive app-owned data.
public struct Context: @unchecked Sendable {
    private var storage: [String: Any]

    internal init(storage: [String: Any]) {
        self.storage = storage
    }

    internal subscript<Value: Sendable>(_ key: ContextKey<Value>) -> Value? {
        get { storage[key.rawValue] as? Value }
        set { storage[key.rawValue] = newValue }
    }

    internal func toBuilder() -> Builder {
        Builder(storage: storage)
    }

    /// Builder for ``Context``.
    ///
    /// Context can hold one authz value (login ID or access token) plus optional account display name.
    /// The builder stores authz values as provided and does not normalize or validate login IDs. Mutating a builder does
    /// not change a ``Context`` that was already built. Assign `nil` through in-place context updates to clear a
    /// previously registered value.
    public struct Builder: @unchecked Sendable {
        private var storage: [String: Any]

        public init() {
            self.storage = [:]
        }

        internal init(storage: [String: Any]) {
            self.storage = storage
        }

        internal subscript<Value: Sendable>(_ key: ContextKey<Value>) -> Value? {
            get { storage[key.rawValue] as? Value }
            set { storage[key.rawValue] = newValue }
        }

        public var authz: Authz? {
            get { self[ContextKeys.authz] }
            set { self[ContextKeys.authz] = newValue }
        }

        public var accountDisplayName: String? {
            get { self[ContextKeys.accountDisplayName] }
            set { self[ContextKeys.accountDisplayName] = newValue }
        }

        public func build(scopeName: String) -> Context {
            var storage = storage
            storage[ContextKeys.scopeName.rawValue] = scopeName
            return Context(storage: storage)
        }
    }
}

private enum ContextKeys {
    fileprivate static let scopeName: ContextKey<String> = ContextKey<String>("scopeName")
    fileprivate static let authz: ContextKey<Authz> = ContextKey<Authz>("authz")
    fileprivate static let accountDisplayName: ContextKey<String> = ContextKey<String>("accountDisplayName")
}

extension Context {
    internal var authz: Authz? {
        self[ContextKeys.authz]
    }

    internal var accountDisplayName: String? {
        self[ContextKeys.accountDisplayName]
    }

    internal var accessToken: AccessToken? {
        guard let authz else { return nil }
        switch authz.wrapper {
        case .fromAccessToken(let token):
            return token
        case .rawLoginIDAuthz, .typedLoginIDAuthz:
            return nil
        }
    }

    internal var loginID: LoginID? {
        guard let authz else { return nil }
        switch authz.wrapper {
        case .typedLoginIDAuthz(let loginID):
            return loginID
        case .rawLoginIDAuthz, .fromAccessToken:
            return nil
        }
    }

    internal var rawLoginID: String? {
        guard let authz else { return nil }
        switch authz.wrapper {
        case .rawLoginIDAuthz(let id):
            return id
        case .typedLoginIDAuthz, .fromAccessToken:
            return nil
        }
    }

    /// Resolves this context's authz into a typed ``LoginID`` when possible.
    ///
    /// Typed login-ID authz is returned unchanged. Access-token authz and missing authz return `nil`. Raw login-ID
    /// authz requires `loginIDValidator` and maps validation failures into ``LoginIDResolutionError`` so consuming
    /// layers can expose their own public failure models.
    internal func loginID(loginIDValidator: (any LoginIDValidator)?) throws(LoginIDResolutionError) -> LoginID? {
        guard let authz else { return nil }
        switch authz.wrapper {
        case .rawLoginIDAuthz(let id):
            guard let loginIDValidator else {
                throw .missingLoginIDValidator(
                    errorCode: .missingCapabilityProvider,
                    message: "Context.loginID(): LoginIDValidator required"
                )
            }
            do {
                return try loginIDValidator.appendWithType(id)
            } catch {
                switch error {
                case .typeNotSupported(_, let message):
                    throw .loginIDTypeNotSupported(errorCode: error.errorCode, message: message)
                case .validationFailed(_, let message, let loginID, let regex):
                    throw .loginIDValidation(errorCode: error.errorCode, message: message, loginID: loginID, regex: regex)
                }
            }
        case .typedLoginIDAuthz(let loginID):
            return loginID
        case .fromAccessToken:
            return nil
        }
    }

    /// Builds the context payload exposed to WebBridge.
    ///
    /// Only the supported bridge-facing context fields are emitted. The payload may contain login identifiers or access
    /// tokens and must be treated as sensitive by consumers.
    internal func toWebBridgePayload() -> JSONValue {
        var payload: [String: JSONValue] = [:]

        if let authz {
            switch authz.wrapper {
            case .rawLoginIDAuthz(let id):
                payload["authz"] = JSONValue(["loginId": JSONValue(id)])
            case .typedLoginIDAuthz(let loginID):
                payload["authz"] = JSONValue(["loginId": JSONValue(loginID.id)])
            case .fromAccessToken(let token):
                let authzPayload: [String: JSONValue] = ["accessToken": JSONValue(token.token)]
                payload["authz"] = JSONValue(authzPayload)
            }
        }

        if let accountDisplayName {
            payload["accountDisplayName"] = JSONValue(accountDisplayName)
        }

        return JSONValue(payload)
    }
}

internal enum LoginIDResolutionError: Error, Sendable, CustomStringConvertible {
    case missingLoginIDValidator(errorCode: ErrorCode, message: String)
    case loginIDTypeNotSupported(errorCode: ErrorCode, message: String)
    case loginIDValidation(errorCode: ErrorCode, message: String, loginID: LoginID, regex: String)

    internal var errorCode: ErrorCode {
        switch self {
        case .missingLoginIDValidator(let errorCode, _): return errorCode
        case .loginIDTypeNotSupported(let errorCode, _): return errorCode
        case .loginIDValidation(let errorCode, _, _, _): return errorCode
        }
    }

    internal var message: String {
        switch self {
        case .missingLoginIDValidator(_, let message): return message
        case .loginIDTypeNotSupported(_, let message): return message
        case .loginIDValidation(_, let message, _, _): return message
        }
    }

    internal var description: String {
        switch self {
        case .missingLoginIDValidator:
            return "LoginIDResolutionError.MissingLoginIDValidator(errorCode=\(errorCode), message=\(message))"
        case .loginIDTypeNotSupported:
            return "LoginIDResolutionError.LoginIDTypeNotSupported(errorCode=\(errorCode), message=\(message))"
        case .loginIDValidation(_, _, let loginID, let regex):
            return
                "LoginIDResolutionError.LoginIDValidation(errorCode=\(errorCode), message=\(message), loginID=\(loginID), regex=\(regex))"
        }
    }
}

extension DIContainerRegistrar where Self: DIContainerResolver {
    public func withContext(_ scopeName: String = "Context", _ block: (inout Context.Builder) -> Void) -> any DIContainer {
        let child = createScope(scopeName: "\(self.scopeName) <- \(scopeName)")
        var builder: Context.Builder = Context.Builder()
        block(&builder)
        child.register(Context.self, instance: builder.build(scopeName: child.scopeName))
        return child
    }

    /// Updates the ``Context`` in the current scope in place.
    ///
    /// Fields assigned in `block` replace existing values, fields not assigned keep their existing values, and assigning
    /// `nil` clears that field.
    public func setContext(_ block: (inout Context.Builder) -> Void) -> Self {
        var builder = getOrNil(type: Context.self)?.toBuilder() ?? Context.Builder()
        block(&builder)
        register(Context.self, instance: builder.build(scopeName: self.scopeName))
        return self
    }

    public func clearContext() -> Self {
        remove(Context.self)
        return self
    }
}
