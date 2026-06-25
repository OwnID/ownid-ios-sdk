import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

final class FlowOperationBox<Params: CapabilityParams, Success: Sendable, Failure: OperationFailure>: @unchecked Sendable {
    private let lock = NSLock()
    private var startResults: [OperationResult<Success, Failure>]

    var availability: Availability
    private(set) var availabilityParams: [Params?] = []
    private(set) var startParams: [Params?] = []
    private(set) var scopedContexts: [Context?] = []

    init(
        availability: Availability = .available,
        startResults: [OperationResult<Success, Failure>]
    ) {
        self.availability = availability
        self.startResults = startResults
    }

    func recordAvailability(params: (any CapabilityParams)?, context: Context?) -> Availability {
        lock.withLock {
            availabilityParams.append(params as? Params)
            scopedContexts.append(context)
            return availability
        }
    }

    func makeController(
        operationType: OperationType,
        params: Params?,
        context: Context?
    ) -> any OperationController<Success, Failure> {
        let result = lock.withLock {
            startParams.append(params)
            scopedContexts.append(context)
            if startResults.count > 1 {
                return startResults.removeFirst()
            }
            return startResults[0]
        }

        let controller = OperationControllerImpl<Success, Failure>(
            operationID: OperationID(type: operationType, id: UUID().uuidString),
            onUserAborted: { _ in }
        )
        switch result {
        case .success(let success):
            controller.complete(success)
        case .canceled(let reason):
            controller.cancel(reason)
        case .failure(let failure):
            controller.fail(failure)
        }
        return controller
    }
}

final class FlowRepositoryFake: UserRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLastUser: User?
    private(set) var lastUserCallCount = 0
    private(set) var savedUsers: [User] = []

    init(lastUser: User? = nil) {
        self.storedLastUser = lastUser
    }

    func lastUser() async throws -> User? {
        lock.withLock {
            lastUserCallCount += 1
            return storedLastUser
        }
    }

    func setLastUser(_ user: User) async throws {
        lock.withLock {
            storedLastUser = user
            savedUsers.append(user)
        }
    }

    func clearLastUser() async {
        lock.withLock {
            storedLastUser = nil
        }
    }
}

final class FlowSessionCreateFake: SessionCreate, @unchecked Sendable {
    private let lock = NSLock()
    private let available: Bool
    private let session: (any Sendable)?
    private(set) var availabilityParams: [SessionCreateParams?] = []
    private(set) var createParams: [SessionCreateParams] = []

    init(available: Bool = true, session: (any Sendable)? = "host-session") {
        self.available = available
        self.session = session
    }

    @MainActor func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        lock.withLock {
            availabilityParams.append(params as? SessionCreateParams)
        }
        return available
    }

    @MainActor func create(params: SessionCreateParams) async -> Result<SessionOutput, any Error & Sendable> {
        lock.withLock {
            createParams.append(params)
        }
        return .success(SessionOutput(session: session))
    }
}

final class FlowLoginIDValidatorFake: LoginIDValidator, @unchecked Sendable {
    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        if loginID.contains("@") { return .email }
        if loginID.first == "+" { return .phoneNumber }
        return .userName
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        loginID
    }
}

final class FlowLoginOperationFake: LoginOperation, @unchecked Sendable {
    let operationType: OperationType = .sessionCreation
    private let box: FlowOperationBox<LoginOperationParams, LoginResponse, LoginOperationFailure>
    private let context: Context?

    init(box: FlowOperationBox<LoginOperationParams, LoginResponse, LoginOperationFailure>, context: Context?) {
        self.box = box
        self.context = context
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        box.recordAvailability(params: params, context: context)
    }

    func start(params: LoginOperationParams?) -> any OperationController<LoginResponse, LoginOperationFailure> {
        box.makeController(operationType: operationType, params: params, context: context)
    }
}

final class FlowLoginIDCollectOperationFake: LoginIDCollectOperation, @unchecked Sendable {
    let operationType: OperationType = .loginIDCollect
    private let box: FlowOperationBox<LoginIDCollectOperationParams, LoginID, LoginIDCollectOperationFailure>
    private let context: Context?

    init(box: FlowOperationBox<LoginIDCollectOperationParams, LoginID, LoginIDCollectOperationFailure>, context: Context?) {
        self.box = box
        self.context = context
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        box.recordAvailability(params: params, context: context)
    }

    func start(params: LoginIDCollectOperationParams?) -> any OperationController<LoginID, LoginIDCollectOperationFailure> {
        box.makeController(operationType: operationType, params: params, context: context)
    }
}

final class FlowPasskeyAttestationOperationFake: PasskeyAttestationOperation, @unchecked Sendable {
    let operationType: OperationType = .passkeyCreation
    private let box: FlowOperationBox<PasskeyAttestationOperationParams, AttestationResponse, PasskeyAttestationOperationFailure>
    private let context: Context?

    init(
        box: FlowOperationBox<PasskeyAttestationOperationParams, AttestationResponse, PasskeyAttestationOperationFailure>,
        context: Context?
    ) {
        self.box = box
        self.context = context
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        box.recordAvailability(params: params, context: context)
    }

    func start(params: PasskeyAttestationOperationParams?) -> any OperationController<
        AttestationResponse, PasskeyAttestationOperationFailure
    > {
        box.makeController(operationType: operationType, params: params, context: context)
    }
}

final class FlowPasskeyEnrollOperationFake: PasskeyEnrollOperation, @unchecked Sendable {
    let operationType: OperationType = .passkeyEnrollment
    private let box: FlowOperationBox<PasskeyEnrollOperationParams, Void, PasskeyEnrollOperationFailure>
    private let context: Context?

    init(box: FlowOperationBox<PasskeyEnrollOperationParams, Void, PasskeyEnrollOperationFailure>, context: Context?) {
        self.box = box
        self.context = context
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        box.recordAvailability(params: params, context: context)
    }

    func start(params: PasskeyEnrollOperationParams?) -> any OperationController<Void, PasskeyEnrollOperationFailure> {
        box.makeController(operationType: operationType, params: params, context: context)
    }
}

final class FlowEmailVerificationOperationFake: EmailVerificationOperation, @unchecked Sendable {
    let operationType: OperationType = .emailVerification
    private let box: FlowOperationBox<EmailVerificationOperationParams, AccessOrProofToken, EmailVerificationOperationFailure>
    private let context: Context?

    init(
        box: FlowOperationBox<EmailVerificationOperationParams, AccessOrProofToken, EmailVerificationOperationFailure>,
        context: Context?
    ) {
        self.box = box
        self.context = context
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        box.recordAvailability(params: params, context: context)
    }

    func start(params: EmailVerificationOperationParams?) -> any OperationController<
        AccessOrProofToken, EmailVerificationOperationFailure
    > {
        box.makeController(operationType: operationType, params: params, context: context)
    }
}

final class FlowPhoneVerificationOperationFake: PhoneVerificationOperation, @unchecked Sendable {
    let operationType: OperationType = .phoneNumberVerification
    private let box: FlowOperationBox<PhoneVerificationOperationParams, AccessOrProofToken, PhoneVerificationOperationFailure>
    private let context: Context?

    init(
        box: FlowOperationBox<PhoneVerificationOperationParams, AccessOrProofToken, PhoneVerificationOperationFailure>,
        context: Context?
    ) {
        self.box = box
        self.context = context
    }

    func availability(params: (any CapabilityParams)?) async -> Availability {
        box.recordAvailability(params: params, context: context)
    }

    func start(params: PhoneVerificationOperationParams?) -> any OperationController<
        AccessOrProofToken, PhoneVerificationOperationFailure
    > {
        box.makeController(operationType: operationType, params: params, context: context)
    }
}

final class FlowBoostLoginFlowFake: BoostLoginFlow, @unchecked Sendable {
    private let lock = NSLock()
    private let result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>
    private(set) var contexts: [BoostFlowContext] = []

    init(result: FlowResult<BoostFlowLoginResponse, BoostLoginFlowFailure>) {
        self.result = result
    }

    func start(_ context: BoostFlowContext) -> any BoostLoginFlowController {
        lock.withLock {
            contexts.append(context)
        }
        let controller = FlowController<BoostFlowLoginResponse, BoostLoginFlowFailure>(onUserAborted: { _ in })
        switch result {
        case .success(let response):
            controller.complete(response)
        case .canceled(let reason):
            controller.cancel(reason)
        case .failure(let failure):
            controller.fail(failure)
        }
        return controller
    }
}

struct FlowTestHarness {
    let container: DIContainerImpl
    let operation: OwnIDOperation
    let taskScope: TaskScope
    let validator: FlowLoginIDValidatorFake
    let coder: JSONCoderImpl
    let login: FlowOperationBox<LoginOperationParams, LoginResponse, LoginOperationFailure>
    let loginIDCollect: FlowOperationBox<LoginIDCollectOperationParams, LoginID, LoginIDCollectOperationFailure>
    let passkeyAttestation: FlowOperationBox<PasskeyAttestationOperationParams, AttestationResponse, PasskeyAttestationOperationFailure>
    let passkeyEnroll: FlowOperationBox<PasskeyEnrollOperationParams, Void, PasskeyEnrollOperationFailure>
    let emailVerification: FlowOperationBox<EmailVerificationOperationParams, AccessOrProofToken, EmailVerificationOperationFailure>
    let phoneVerification: FlowOperationBox<PhoneVerificationOperationParams, AccessOrProofToken, PhoneVerificationOperationFailure>

    init(
        loginResult: OperationResult<LoginResponse, LoginOperationFailure>,
        loginIDCollectResult: OperationResult<LoginID, LoginIDCollectOperationFailure> = .success(
            FlowFixtures.loginID("collected@example.com")
        ),
        passkeyAttestationResult: OperationResult<AttestationResponse, PasskeyAttestationOperationFailure> = .success(
            FlowFixtures.attestationResponse()
        ),
        passkeyEnrollResult: OperationResult<Void, PasskeyEnrollOperationFailure> = .success(()),
        emailVerificationResult: OperationResult<AccessOrProofToken, EmailVerificationOperationFailure> = .success(
            .accessToken(FlowFixtures.accessToken(id: "email-verification@example.test"))
        ),
        phoneVerificationResult: OperationResult<AccessOrProofToken, PhoneVerificationOperationFailure> = .success(
            .accessToken(FlowFixtures.accessToken(id: "+15550100200", type: .phoneNumber))
        )
    ) {
        container = DIContainerImpl(scopeName: "flow-tests")
        taskScope = TaskScope(shutdownToken: ShutdownToken())
        validator = FlowLoginIDValidatorFake()
        coder = JSONCoderImpl()
        let loginBox = FlowOperationBox<LoginOperationParams, LoginResponse, LoginOperationFailure>(startResults: [loginResult])
        let loginIDCollectBox = FlowOperationBox<LoginIDCollectOperationParams, LoginID, LoginIDCollectOperationFailure>(
            startResults: [loginIDCollectResult]
        )
        let passkeyAttestationBox = FlowOperationBox<
            PasskeyAttestationOperationParams,
            AttestationResponse,
            PasskeyAttestationOperationFailure
        >(startResults: [passkeyAttestationResult])
        let passkeyEnrollBox = FlowOperationBox<PasskeyEnrollOperationParams, Void, PasskeyEnrollOperationFailure>(
            startResults: [passkeyEnrollResult]
        )
        let emailVerificationBox = FlowOperationBox<
            EmailVerificationOperationParams,
            AccessOrProofToken,
            EmailVerificationOperationFailure
        >(startResults: [emailVerificationResult])
        let phoneVerificationBox = FlowOperationBox<
            PhoneVerificationOperationParams,
            AccessOrProofToken,
            PhoneVerificationOperationFailure
        >(startResults: [phoneVerificationResult])
        login = loginBox
        loginIDCollect = loginIDCollectBox
        passkeyAttestation = passkeyAttestationBox
        passkeyEnroll = passkeyEnrollBox
        emailVerification = emailVerificationBox
        phoneVerification = phoneVerificationBox

        container.register(InstanceName.self, instance: InstanceName(value: "FLOW_TESTS"))
        container.register((any JSONCoder).self, instance: coder)
        container.register((any LoginIDValidator).self, instance: validator)
        container.register(TaskScope.self, instance: taskScope)
        container.registerFactory((any LoginOperation).self, dependencies: []) { resolver in
            FlowLoginOperationFake(box: loginBox, context: resolver.getOrNil(type: Context.self))
        }
        container.registerFactory((any LoginIDCollectOperation).self, dependencies: []) { resolver in
            FlowLoginIDCollectOperationFake(box: loginIDCollectBox, context: resolver.getOrNil(type: Context.self))
        }
        container.registerFactory((any PasskeyAttestationOperation).self, dependencies: []) { resolver in
            FlowPasskeyAttestationOperationFake(box: passkeyAttestationBox, context: resolver.getOrNil(type: Context.self))
        }
        container.registerFactory((any PasskeyEnrollOperation).self, dependencies: []) { resolver in
            FlowPasskeyEnrollOperationFake(box: passkeyEnrollBox, context: resolver.getOrNil(type: Context.self))
        }
        container.registerFactory((any EmailVerificationOperation).self, dependencies: []) { resolver in
            FlowEmailVerificationOperationFake(box: emailVerificationBox, context: resolver.getOrNil(type: Context.self))
        }
        container.registerFactory((any PhoneVerificationOperation).self, dependencies: []) { resolver in
            FlowPhoneVerificationOperationFake(box: phoneVerificationBox, context: resolver.getOrNil(type: Context.self))
        }

        operation = container.opsNamespace
    }
}

enum FlowFixtures {
    static func loginID(_ id: String = "person@example.com", type: LoginIDType = .email) -> LoginID {
        LoginID(id: id, type: type)
    }

    static func accessToken(id: String = "person@example.com", type: LoginIDType = .email) -> AccessToken {
        let subject = "\(type.rawValue):\(id)"
        let payload = #"{"sub":"\#(subject)"}"#
        return AccessToken(token: "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(payload)).signature")
    }

    static func loginSuccess(
        id: String = "person@example.com",
        type: LoginIDType = .email,
        sessionPayload: String = #"{"raw":"session"}"#
    ) -> LoginResponse {
        .success(LoginResponse.Success(accessToken: accessToken(id: id, type: type), sessionPayload: sessionPayload))
    }

    static func attestationResponse(
        proofToken: ProofToken = ProofToken(token: "proof-token"),
        ownIdData: String = #"{"own":"data"}"#
    ) -> AttestationResponse {
        AttestationResponse(proofToken: proofToken, ownIdData: ownIdData)
    }

    static func context(authz: Authz) -> Context {
        var builder = Context.Builder()
        builder.authz = authz
        return builder.build(scopeName: "test-context")
    }

    private static func base64URL(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

func requireRecordedValue<Value>(
    _ values: [Value?],
    _ description: Comment,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Value {
    try #require(values.first ?? nil, description, sourceLocation: sourceLocation)
}

func requireLoginOutcome(
    _ response: BoostFlowResponse,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> BoostFlowLoginResponse {
    guard case .login(let login) = response else {
        return try #require(
            nil as BoostFlowLoginResponse?,
            "Expected login terminal outcome, got \(response)",
            sourceLocation: sourceLocation
        )
    }
    return login
}

func requireCreatePasskeyOutcome(
    _ response: BoostFlowResponse,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> BoostFlowCreatePasskeyResponse {
    guard case .createPasskey(let created) = response else {
        return try #require(
            nil as BoostFlowCreatePasskeyResponse?,
            "Expected create-passkey terminal outcome, got \(response)",
            sourceLocation: sourceLocation
        )
    }
    return created
}
