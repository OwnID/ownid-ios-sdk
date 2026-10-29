import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Support-only: shared operation fixtures and assertions for behavior tests.

enum OperationTestTimeout: Error, Sendable {
    case timedOut(String)
    case streamEnded(String)
}

func withOperationTimeout<T: Sendable>(
    _ description: String,
    seconds: UInt64 = 5,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw OperationTestTimeout.timedOut(description)
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

func requireOperationSuccess<Success: Sendable, Failure: OperationFailure>(
    _ result: OperationResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Success {
    switch result {
    case .success(let success):
        return success
    case .canceled(let reason):
        return try #require(nil as Success?, "Expected success, got cancellation: \(reason)", sourceLocation: sourceLocation)
    case .failure(let failure):
        return try #require(nil as Success?, "Expected success, got failure: \(failure)", sourceLocation: sourceLocation)
    }
}

func requireOperationFailure<Success: Sendable, Failure: OperationFailure>(
    _ result: OperationResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Failure {
    switch result {
    case .failure(let failure):
        return failure
    case .success(let success):
        return try #require(nil as Failure?, "Expected failure, got success: \(success)", sourceLocation: sourceLocation)
    case .canceled(let reason):
        return try #require(nil as Failure?, "Expected failure, got cancellation: \(reason)", sourceLocation: sourceLocation)
    }
}

func requireOperationCancellation<Success: Sendable, Failure: OperationFailure>(
    _ result: OperationResult<Success, Failure>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Reason {
    switch result {
    case .canceled(let reason):
        return reason
    case .success(let success):
        return try #require(nil as Reason?, "Expected cancellation, got success: \(success)", sourceLocation: sourceLocation)
    case .failure(let failure):
        return try #require(nil as Reason?, "Expected cancellation, got failure: \(failure)", sourceLocation: sourceLocation)
    }
}

func assertAvailable(
    _ availability: Availability,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    guard case .available = availability else {
        Issue.record("Expected availability, got \(availability)", sourceLocation: sourceLocation)
        return
    }
}

func assertUnavailable(
    _ availability: Availability,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    guard case .unavailable = availability else {
        Issue.record("Expected unavailability, got \(availability)", sourceLocation: sourceLocation)
        return
    }
}

actor CapturedValue<Value: Sendable> {
    private var value: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []
    private var cancellableWaiters: [UUID: CheckedContinuation<Value, any Error>] = [:]

    func set(_ value: Value) {
        self.value = value
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume(returning: value) }
        let cancellableWaiters = cancellableWaiters
        self.cancellableWaiters.removeAll()
        for waiter in cancellableWaiters.values { waiter.resume(returning: value) }
    }

    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func waitUnlessCancelled() async throws -> Value {
        if let value { return value }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let value {
                    continuation.resume(returning: value)
                } else {
                    cancellableWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        cancellableWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

@MainActor
final class MainActorCapturedValue<Value: Sendable> {
    private var value: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []
    private var cancellableWaiters: [UUID: CheckedContinuation<Value, any Error>] = [:]

    func set(_ value: Value) {
        self.value = value
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume(returning: value) }
        let cancellableWaiters = cancellableWaiters
        self.cancellableWaiters.removeAll()
        for waiter in cancellableWaiters.values { waiter.resume(returning: value) }
    }

    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func waitUnlessCancelled() async throws -> Value {
        if let value { return value }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let value {
                    continuation.resume(returning: value)
                } else {
                    cancellableWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        cancellableWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func get() -> Value { lock.withLock { value } }
    func set(_ value: Value) { lock.withLock { self.value = value } }
    @discardableResult func mutate<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}

func testTaskScope() -> TaskScope { TaskScope(shutdownToken: ShutdownToken()) }
func testLoginID(_ id: String = "user@example.test", type: LoginIDType = .email) -> LoginID { LoginID(id: id, type: type) }
func testAccessToken(_ token: String = "access-token") -> AccessToken { AccessToken(token: token) }
func testProofToken(_ token: String = "proof-token") -> ProofToken { ProofToken(token: token) }

func testContext(authz: Authz, accountDisplayName: String? = nil) -> Context {
    var builder = Context.Builder()
    builder.authz = authz
    builder.accountDisplayName = accountDisplayName
    return builder.build(scopeName: "operation-tests")
}

func testLoginResponse(_ token: String = "login-access-token") -> LoginResponse {
    .success(.init(accessToken: testAccessToken(token), sessionPayload: #"{"session":true}"#))
}

func testVerificationChallenge(
    _ id: String = "verification-challenge",
    channel: OperationChannel = OperationChannel(channel: "user@example.test", id: "channel-id")
) -> VerificationChallenge {
    VerificationChallenge(
        challengeID: ChallengeID(id),
        resendPolicy: .init(allow: true, attempts: 3, debounce: 1),
        timeout: Timeout(milliseconds: 10_000),
        attempts: 3,
        methods: .init(otp: .init(length: 6), magicLink: nil),
        channel: channel
    )
}

func testAssertionOptions(_ challenge: String = "assertion-challenge") -> AssertionOptions {
    AssertionOptions(
        challenge: ChallengeID(challenge),
        rpID: "login.example.test",
        allowCredentials: [PublicKeyCredentialDescriptor(id: "credential-id", type: .publicKey, transports: [.internal])],
        userVerification: .preferred,
        timeout: Timeout(milliseconds: 10_000)
    )
}

func testAssertionResult(_ id: String = "assertion-credential-id") -> AssertionResult {
    AssertionResult(
        id: id,
        type: .publicKey,
        response: .init(
            clientDataJSON: "client-data-json",
            authenticatorData: "authenticator-data",
            signature: "signature",
            userHandle: "user-handle"
        ),
        authenticatorAttachment: .platform
    )
}

func testAttestationOptions(_ challenge: String = "attestation-challenge") -> AttestationOptions {
    AttestationOptions(
        rp: .init(id: "login.example.test", name: "Example RP"),
        user: .init(id: "dXNlci1oYW5kbGU", name: "user@example.test", displayName: "Test User"),
        challenge: ChallengeID(challenge),
        pubKeyCredParams: [.init(type: .publicKey, alg: .ES256)],
        attestation: .direct,
        authenticatorSelection: .init(authenticatorAttachment: .platform, userVerification: .required, residentKey: .preferred),
        timeout: Timeout(milliseconds: 10_000),
        excludeCredentials: [PublicKeyCredentialDescriptor(id: "credential-id", type: .publicKey, transports: [.internal])]
    )
}

func testAttestationResult(_ id: String = "attestation-credential-id") -> AttestationResult {
    AttestationResult(
        id: id,
        type: .publicKey,
        response: .init(
            clientDataJSON: "client-data-json",
            attestationObject: "attestation-object",
            transports: [.internal, .hybrid]
        ),
        authenticatorAttachment: .platform
    )
}

func testAttestationResponse(
    proofToken: ProofToken = testProofToken("attestation-proof-token"),
    ownIdData: String = #"{"ownId":"data"}"#
) -> AttestationResponse {
    AttestationResponse(proofToken: proofToken, ownIdData: ownIdData)
}

func testSocialChallenge(provider: SocialProviderID, challenge: String = "social-challenge") -> SocialChallenge {
    SocialChallenge(
        challengeID: ChallengeID(challenge),
        timeout: Timeout(milliseconds: 10_000),
        clientID: "\(provider.rawValue.lowercased())-client-id",
        challengeURL: nil
    )
}

func testSocialToken(provider: SocialProviderID, token: String = "social-access-token") -> AccessTokenWithUserInfo {
    AccessTokenWithUserInfo(
        accessToken: testAccessToken(token),
        loginID: testLoginID(),
        userInfo: ["sub": "provider-user"],
        provider: provider
    )
}

final class FakeLoginIDConfigurationProvider: LoginIDConfigurationProvider, @unchecked Sendable {
    private let storage: Locked<LoginIDConfiguration>
    init(configuration: LoginIDConfiguration = .default) { storage = Locked(configuration) }
    var configuration: LoginIDConfiguration { storage.get() }
    func setServerConfiguration(_ configuration: LoginIDConfiguration) { storage.set(configuration) }
    func setConfiguration(_ configuration: LoginIDConfiguration) { storage.set(configuration) }
    func clearConfiguration() {}
}

final class FakeAppConfigProvider: AppConfigProvider, @unchecked Sendable {
    private let storage: Locked<AppConfig?>
    private let onRead: (@Sendable () -> Void)?
    let readCount = Locked(0)

    init(config: AppConfig? = nil, onRead: (@Sendable () -> Void)? = nil) {
        storage = Locked(config)
        self.onRead = onRead
    }

    var currentConfig: AppConfig? {
        readCount.mutate { $0 += 1 }
        let config = storage.get()
        onRead?()
        return config
    }

    func set(_ config: AppConfig?) { storage.set(config) }

    func getOrFetchConfig() async throws -> AppConfig {
        Issue.record("Login ID collect must not fetch AppConfig")
        return storage.get() ?? .default
    }

    var configStream: AsyncStream<AppConfig> {
        Issue.record("Login ID collect must not observe AppConfig")
        return AsyncStream { $0.finish() }
    }
}

final class FakeLoginIDValidator: LoginIDValidator, @unchecked Sendable {
    private let supportedTypes: [LoginIDType]
    private let invalidIDs: Set<String>
    private let onDetermine: (@Sendable (String) -> Void)?
    private let onValidate: (@Sendable (LoginID) -> Void)?
    let determineCalls = Locked<[String]>([])
    let validationCalls = Locked<[LoginID]>([])

    init(
        supportedTypes: [LoginIDType] = [.email, .phoneNumber, .userName],
        invalidIDs: Set<String> = [],
        onDetermine: (@Sendable (String) -> Void)? = nil,
        onValidate: (@Sendable (LoginID) -> Void)? = nil
    ) {
        self.supportedTypes = supportedTypes
        self.invalidIDs = invalidIDs
        self.onDetermine = onDetermine
        self.onValidate = onValidate
    }

    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        determineCalls.mutate { $0.append(loginID) }
        onDetermine?(loginID)
        let type: LoginIDType = loginID.contains("@") ? .email : (loginID.hasPrefix("+") ? .phoneNumber : .userName)
        guard supportedTypes.contains(type) else {
            throw .typeNotSupported(errorCode: .loginIDTypeNotSupported, message: "Unsupported LoginID.Type: \(type)")
        }
        return type
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        validationCalls.mutate { $0.append(loginID) }
        onValidate?(loginID)
        guard supportedTypes.contains(loginID.type) else {
            throw .typeNotSupported(errorCode: .loginIDTypeNotSupported, message: "Unsupported LoginID.Type: \(loginID.type)")
        }
        guard !invalidIDs.contains(loginID.id), !loginID.id.isEmpty else {
            throw .validationFailed(
                errorCode: .loginIDValidationFailed,
                message: "Login ID does not match",
                loginID: loginID,
                regex: "test-regex"
            )
        }
        return loginID
    }
}

final class FakeLoginAPI: LoginAPI, @unchecked Sendable {
    let result: APIResult<LoginResponse, LoginAPIFailure>
    let params = Locked<[LoginAPIParams?]>([])
    init(result: APIResult<LoginResponse, LoginAPIFailure>) { self.result = result }
    func start(params: LoginAPIParams?) async -> APIResult<LoginResponse, LoginAPIFailure> {
        self.params.mutate { $0.append(params) }
        return result
    }
}

final class FakeDiscoverAPI: DiscoverAPI, @unchecked Sendable {
    let result: APIResult<LoginResponse, DiscoverAPIFailure>
    let params = Locked<[DiscoverAPIParams?]>([])
    init(result: APIResult<LoginResponse, DiscoverAPIFailure>) { self.result = result }
    func start(params: DiscoverAPIParams?) async -> APIResult<LoginResponse, DiscoverAPIFailure> {
        self.params.mutate { $0.append(params) }
        return result
    }
}

final class FakeLoginIDCollectUI: LoginIDCollectUI, @unchecked Sendable {
    let startCount = Locked(0)
    let controller = MainActorCapturedValue<any LoginIDCollectOperationController>()
    private let onStart: (@MainActor @Sendable () -> LoginIDCollectOperationFailure.Integration?)?

    init(onStart: (@MainActor @Sendable () -> LoginIDCollectOperationFailure.Integration?)? = nil) {
        self.onStart = onStart
    }

    @MainActor func start(controller: any LoginIDCollectOperationController) -> LoginIDCollectOperationFailure.Integration? {
        startCount.mutate { $0 += 1 }
        self.controller.set(controller)
        return onStart?()
    }
}

final class FakeEmailVerificationUI: EmailVerificationUI, @unchecked Sendable {
    let controller = MainActorCapturedValue<any EmailVerificationOperationController>()
    @MainActor func start(controller: any EmailVerificationOperationController) -> EmailVerificationOperationFailure.Integration? {
        self.controller.set(controller)
        return nil
    }
}

final class FakePhoneVerificationUI: PhoneVerificationUI, @unchecked Sendable {
    let controller = MainActorCapturedValue<any PhoneVerificationOperationController>()
    @MainActor func start(controller: any PhoneVerificationOperationController) -> PhoneVerificationOperationFailure.Integration? {
        self.controller.set(controller)
        return nil
    }
}

final class FakeEmailVerificationAPI: EmailVerificationAPI, @unchecked Sendable {
    let startResult: APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure>
    let params = Locked<[EmailVerificationAPIParams?]>([])

    init(apiController: FakeEmailVerificationAPIController) {
        self.startResult = .success(apiController)
    }

    init(startResult: APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure>) {
        self.startResult = startResult
    }

    func start(params: EmailVerificationAPIParams?) async -> APIResult<any EmailVerificationAPIController, EmailVerificationStartAPIFailure>
    {
        self.params.mutate { $0.append(params) }
        return startResult
    }
}

final class FakeEmailVerificationAPIController: EmailVerificationAPIController, @unchecked Sendable {
    let challenge: VerificationChallenge
    let completeResult: APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>
    let resendHandler: @Sendable () async -> APIResult<Void, EmailVerificationResendAPIFailure>
    let cancelResult: APIResult<Void, EmailVerificationCancelAPIFailure>
    let completedCodes = Locked<[String]>([])
    let resendCalls = Locked(0)
    let cancelReasons = Locked<[Reason]>([])
    let cancelReason = CapturedValue<Reason>()
    init(
        challenge: VerificationChallenge = testVerificationChallenge(),
        completeResult: APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>,
        resendResult: APIResult<Void, EmailVerificationResendAPIFailure> = .success(()),
        cancelResult: APIResult<Void, EmailVerificationCancelAPIFailure> = .success(())
    ) {
        self.challenge = challenge
        self.completeResult = completeResult
        self.resendHandler = { resendResult }
        self.cancelResult = cancelResult
    }

    init(
        challenge: VerificationChallenge = testVerificationChallenge(),
        completeResult: APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure>,
        resendHandler: @escaping @Sendable () async -> APIResult<Void, EmailVerificationResendAPIFailure>,
        cancelResult: APIResult<Void, EmailVerificationCancelAPIFailure> = .success(())
    ) {
        self.challenge = challenge
        self.completeResult = completeResult
        self.resendHandler = resendHandler
        self.cancelResult = cancelResult
    }

    func complete(code: String) async -> APIResult<AccessOrProofToken, EmailVerificationCompleteAPIFailure> {
        completedCodes.mutate { $0.append(code) }
        return completeResult
    }
    func resend() async -> APIResult<Void, EmailVerificationResendAPIFailure> {
        resendCalls.mutate { $0 += 1 }
        return await resendHandler()
    }
    func cancel(reason: Reason) async -> APIResult<Void, EmailVerificationCancelAPIFailure> {
        cancelReasons.mutate { $0.append(reason) }
        await cancelReason.set(reason)
        return cancelResult
    }
}

final class FakePhoneVerificationAPI: PhoneVerificationAPI, @unchecked Sendable {
    let startResult: APIResult<any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>
    let params = Locked<[PhoneVerificationAPIParams?]>([])

    init(apiController: FakePhoneVerificationAPIController) {
        self.startResult = .success(apiController)
    }

    init(startResult: APIResult<any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>) {
        self.startResult = startResult
    }

    func start(params: PhoneVerificationAPIParams?) async -> APIResult<any PhoneVerificationAPIController, PhoneVerificationStartAPIFailure>
    {
        self.params.mutate { $0.append(params) }
        return startResult
    }
}

final class FakePhoneVerificationAPIController: PhoneVerificationAPIController, @unchecked Sendable {
    let challenge: VerificationChallenge
    let completeResult: APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>
    let resendHandler: @Sendable () async -> APIResult<Void, PhoneVerificationResendAPIFailure>
    let cancelResult: APIResult<Void, PhoneVerificationCancelAPIFailure>
    let completedCodes = Locked<[String]>([])
    let resendCalls = Locked(0)
    let cancelReasons = Locked<[Reason]>([])
    let cancelReason = CapturedValue<Reason>()
    init(
        challenge: VerificationChallenge = testVerificationChallenge(),
        completeResult: APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>,
        resendResult: APIResult<Void, PhoneVerificationResendAPIFailure> = .success(()),
        cancelResult: APIResult<Void, PhoneVerificationCancelAPIFailure> = .success(())
    ) {
        self.challenge = challenge
        self.completeResult = completeResult
        self.resendHandler = { resendResult }
        self.cancelResult = cancelResult
    }

    init(
        challenge: VerificationChallenge = testVerificationChallenge(),
        completeResult: APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure>,
        resendHandler: @escaping @Sendable () async -> APIResult<Void, PhoneVerificationResendAPIFailure>,
        cancelResult: APIResult<Void, PhoneVerificationCancelAPIFailure> = .success(())
    ) {
        self.challenge = challenge
        self.completeResult = completeResult
        self.resendHandler = resendHandler
        self.cancelResult = cancelResult
    }

    func complete(code: String) async -> APIResult<AccessOrProofToken, PhoneVerificationCompleteAPIFailure> {
        completedCodes.mutate { $0.append(code) }
        return completeResult
    }
    func resend() async -> APIResult<Void, PhoneVerificationResendAPIFailure> {
        resendCalls.mutate { $0 += 1 }
        return await resendHandler()
    }
    func cancel(reason: Reason) async -> APIResult<Void, PhoneVerificationCancelAPIFailure> {
        cancelReasons.mutate { $0.append(reason) }
        await cancelReason.set(reason)
        return cancelResult
    }
}

@MainActor
final class FakePasskeyAssertionUI: PasskeyAssertionUI, @unchecked Sendable {
    let result: PasskeyResult<AssertionResult>
    private(set) var receivedOptions: AssertionOptions?
    private var available = true
    private(set) var availabilityParams: [(any CapabilityParams)?] = []
    init(result: PasskeyResult<AssertionResult>) { self.result = result }
    func setAvailable(_ value: Bool) { available = value }
    func resetAvailabilityParams() { availabilityParams.removeAll() }
    func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        availabilityParams.append(params)
        return available
    }
    func getCredential(options: AssertionOptions) async -> PasskeyResult<AssertionResult> {
        receivedOptions = options
        return result
    }
}

final class FakePasskeyAssertionAPI: PasskeyAssertionAPI, @unchecked Sendable {
    let apiController: FakePasskeyAssertionAPIController
    let params = Locked<[PasskeyAssertionAPIParams?]>([])
    init(apiController: FakePasskeyAssertionAPIController) { self.apiController = apiController }
    func start(params: PasskeyAssertionAPIParams?) async -> APIResult<any PasskeyAssertionAPIController, PasskeyAssertionStartAPIFailure> {
        self.params.mutate { $0.append(params) }
        return .success(apiController)
    }
}

final class FakePasskeyAssertionAPIController: PasskeyAssertionAPIController, @unchecked Sendable {
    let assertionOptions: AssertionOptions
    let verifyResult: APIResult<AccessToken, PasskeyAssertionVerifyAPIFailure>
    let cancelResult: APIResult<Void, PasskeyAssertionCancelAPIFailure>
    let assertionResults = Locked<[AssertionResult]>([])
    let cancelReasons = Locked<[Reason]>([])
    init(
        assertionOptions: AssertionOptions = testAssertionOptions(),
        verifyResult: APIResult<AccessToken, PasskeyAssertionVerifyAPIFailure> = .success(testAccessToken("assertion-access-token")),
        cancelResult: APIResult<Void, PasskeyAssertionCancelAPIFailure> = .success(())
    ) {
        self.assertionOptions = assertionOptions
        self.verifyResult = verifyResult
        self.cancelResult = cancelResult
    }
    func verify(assertionResult: AssertionResult) async -> APIResult<AccessToken, PasskeyAssertionVerifyAPIFailure> {
        assertionResults.mutate { $0.append(assertionResult) }
        return verifyResult
    }
    func cancel(reason: Reason) async -> APIResult<Void, PasskeyAssertionCancelAPIFailure> {
        cancelReasons.mutate { $0.append(reason) }
        return cancelResult
    }
}

@MainActor
final class FakePasskeyAttestationUI: PasskeyAttestationUI, @unchecked Sendable {
    let result: PasskeyResult<AttestationResult>
    private(set) var receivedOptions: AttestationOptions?
    private var available = true
    private(set) var availabilityParams: [(any CapabilityParams)?] = []
    init(result: PasskeyResult<AttestationResult>) { self.result = result }
    func setAvailable(_ value: Bool) { available = value }
    func resetAvailabilityParams() { availabilityParams.removeAll() }
    func isAvailable(params: (any CapabilityParams)?) async -> Bool {
        availabilityParams.append(params)
        return available
    }
    func createCredential(options: AttestationOptions) async -> PasskeyResult<AttestationResult> {
        receivedOptions = options
        return result
    }
}

final class FakePasskeyAttestationAPI: PasskeyAttestationAPI, @unchecked Sendable {
    let apiController: FakePasskeyAttestationAPIController
    let params = Locked<[PasskeyAttestationAPIParams?]>([])
    init(apiController: FakePasskeyAttestationAPIController) { self.apiController = apiController }
    func start(params: PasskeyAttestationAPIParams?) async -> APIResult<
        any PasskeyAttestationAPIController, PasskeyAttestationStartAPIFailure
    > {
        self.params.mutate { $0.append(params) }
        return .success(apiController)
    }
}

final class FakePasskeyAttestationAPIController: PasskeyAttestationAPIController, @unchecked Sendable {
    let attestationOptions: AttestationOptions
    let verifyResult: APIResult<AttestationResponse, PasskeyAttestationVerifyAPIFailure>
    let cancelResult: APIResult<Void, PasskeyAttestationCancelAPIFailure>
    let attestationResults = Locked<[AttestationResult]>([])
    let cancelReasons = Locked<[Reason]>([])
    init(
        attestationOptions: AttestationOptions = testAttestationOptions(),
        verifyResult: APIResult<AttestationResponse, PasskeyAttestationVerifyAPIFailure> = .success(testAttestationResponse()),
        cancelResult: APIResult<Void, PasskeyAttestationCancelAPIFailure> = .success(())
    ) {
        self.attestationOptions = attestationOptions
        self.verifyResult = verifyResult
        self.cancelResult = cancelResult
    }
    func verify(attestationResult: AttestationResult) async -> APIResult<AttestationResponse, PasskeyAttestationVerifyAPIFailure> {
        attestationResults.mutate { $0.append(attestationResult) }
        return verifyResult
    }
    func cancel(reason: Reason) async -> APIResult<Void, PasskeyAttestationCancelAPIFailure> {
        cancelReasons.mutate { $0.append(reason) }
        return cancelResult
    }
}

final class FakePasskeyEnrollAPI: PasskeyEnrollAPI, @unchecked Sendable {
    let result: APIResult<Void, PasskeyEnrollAPIFailure>
    let params = Locked<[PasskeyEnrollAPIParams]>([])
    init(result: APIResult<Void, PasskeyEnrollAPIFailure> = .success(())) { self.result = result }
    func start(params: PasskeyEnrollAPIParams) async -> APIResult<Void, PasskeyEnrollAPIFailure> {
        self.params.mutate { $0.append(params) }
        return result
    }
}

final class FakeOIDCAPI: OIDCAPI, @unchecked Sendable {
    let startResult: APIResult<any OIDCAPIController, OIDCStartAPIFailure>
    let params = Locked<[OIDCAPIParams?]>([])
    init(controller: FakeOIDCAPIController) { self.startResult = .success(controller) }
    init(startResult: APIResult<any OIDCAPIController, OIDCStartAPIFailure>) { self.startResult = startResult }
    func start(params: OIDCAPIParams?) async -> APIResult<any OIDCAPIController, OIDCStartAPIFailure> {
        self.params.mutate { $0.append(params) }
        return startResult
    }
}

final class FakeOIDCAPIController: OIDCAPIController, @unchecked Sendable {
    let challenge: SocialChallenge
    let completeResult: APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure>
    let cancelResult: APIResult<Void, OIDCCancelAPIFailure>
    let idTokens = Locked<[String]>([])
    let cancelReasons = Locked<[Reason]>([])
    let cancelReason = CapturedValue<Reason>()
    init(
        challenge: SocialChallenge,
        completeResult: APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure>,
        cancelResult: APIResult<Void, OIDCCancelAPIFailure> = .success(())
    ) {
        self.challenge = challenge
        self.completeResult = completeResult
        self.cancelResult = cancelResult
    }
    func completeWithToken(idToken: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> {
        idTokens.mutate { $0.append(idToken) }
        return completeResult
    }
    func completeWithCode(code: String) async -> APIResult<AccessTokenWithUserInfo, OIDCCompleteAPIFailure> {
        .failure(.badRequest(.invalidArgument(errorCode: .invalidArgument, message: "Unexpected code response")))
    }
    func cancel(reason: Reason) async -> APIResult<Void, OIDCCancelAPIFailure> {
        cancelReasons.mutate { $0.append(reason) }
        await cancelReason.set(reason)
        return cancelResult
    }
}

@MainActor
final class FakeAppleSignInUI: SignInWithAppleUI, @unchecked Sendable {
    let result: SocialSignInResult?
    let started = MainActorCapturedValue<Void>()
    let canceled = MainActorCapturedValue<Void>()
    let completion = MainActorCapturedValue<SocialSignInResult>()
    private(set) var receivedClientID: String?
    private(set) var receivedNonce: String?
    private(set) var signInCallCount = 0
    private(set) var cancelCallCount = 0
    init(result: SocialSignInResult? = nil) { self.result = result }
    func signIn(clientID: String, nonce: String?) async -> SocialSignInResult {
        receivedClientID = clientID
        receivedNonce = nonce
        signInCallCount += 1
        started.set(())
        if let result { return result }
        do {
            return try await completion.waitUnlessCancelled()
        } catch {
            return .canceled(reason: .systemError(details: "Fake Apple UI task canceled"))
        }
    }
    func cancel() {
        cancelCallCount += 1
        canceled.set(())
    }
}

@MainActor
final class FakeGoogleSignInUI: SignInWithGoogleUI, @unchecked Sendable {
    let result: SocialSignInResult?
    let started = MainActorCapturedValue<Void>()
    let canceled = MainActorCapturedValue<Void>()
    let completion = MainActorCapturedValue<SocialSignInResult>()
    private(set) var receivedClientID: String?
    private(set) var receivedNonce: String?
    private(set) var signInCallCount = 0
    private(set) var cancelCallCount = 0
    init(result: SocialSignInResult? = nil) { self.result = result }
    func signIn(clientID: String, nonce: String?) async -> SocialSignInResult {
        receivedClientID = clientID
        receivedNonce = nonce
        signInCallCount += 1
        started.set(())
        if let result { return result }
        do {
            return try await completion.waitUnlessCancelled()
        } catch {
            return .canceled(reason: .systemError(details: "Fake Google UI task canceled"))
        }
    }
    func cancel() {
        cancelCallCount += 1
        canceled.set(())
    }
}

func nextEmailActiveState(
    from controller: any EmailVerificationOperationController,
    where predicate: @escaping @Sendable (EmailVerificationUIState) -> Bool = { _ in true }
) async throws -> EmailVerificationUIState {
    let stream = await MainActor.run { controller.stateStream() }
    return try await withOperationTimeout("email verification active state") {
        for await state in stream {
            if case .active(let uiState, _) = state, predicate(uiState) { return uiState }
        }
        throw OperationTestTimeout.streamEnded("email verification active state")
    }
}

func nextEmailCompletedResult(
    from controller: any EmailVerificationOperationController,
    seconds: UInt64 = 5
) async throws -> OperationResult<AccessOrProofToken, EmailVerificationOperationFailure> {
    let stream = await MainActor.run { controller.stateStream() }
    return try await withOperationTimeout("email verification completed state", seconds: seconds) {
        for await state in stream {
            if case .completed(let result) = state { return result }
        }
        throw OperationTestTimeout.streamEnded("email verification completed state")
    }
}

func nextPhoneActiveState(
    from controller: any PhoneVerificationOperationController,
    where predicate: @escaping @Sendable (PhoneVerificationUIState) -> Bool = { _ in true }
) async throws -> PhoneVerificationUIState {
    let stream = await MainActor.run { controller.stateStream() }
    return try await withOperationTimeout("phone verification active state") {
        for await state in stream {
            if case .active(let uiState, _) = state, predicate(uiState) { return uiState }
        }
        throw OperationTestTimeout.streamEnded("phone verification active state")
    }
}

func nextPhoneCompletedResult(
    from controller: any PhoneVerificationOperationController,
    seconds: UInt64 = 5
) async throws -> OperationResult<AccessOrProofToken, PhoneVerificationOperationFailure> {
    let stream = await MainActor.run { controller.stateStream() }
    return try await withOperationTimeout("phone verification completed state", seconds: seconds) {
        for await state in stream {
            if case .completed(let result) = state { return result }
        }
        throw OperationTestTimeout.streamEnded("phone verification completed state")
    }
}
