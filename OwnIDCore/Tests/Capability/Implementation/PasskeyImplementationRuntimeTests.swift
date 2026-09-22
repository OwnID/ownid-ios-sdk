import AuthenticationServices
import Foundation
import Testing
import UIKit

@_spi(OwnIDInternal) @testable import OwnIDCore

// Covers: PASSKEY-CAPABILITY-020, PASSKEY-CAPABILITY-030
@MainActor
@Suite(.serialized)
struct PasskeyImplementationRuntimeTests {

    @Test func `Presentation anchor uses the supplied window`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let expectedWindow = makeTestWindow()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)
        let task = Task {
            await passkey.createCredential(window: expectedWindow, attestationOptions: attestationOptions())
        }
        let controller = try await factory.waitForController()

        #expect(passkey.presentationAnchor(for: makeAuthorizationController()) === expectedWindow)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test func `Create credential builds platform registration request and performs without options`() async throws {
        guard #available(iOS 17.4, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let options = attestationOptions(
            challenge: Data("attestation challenge".utf8),
            userID: Data("user handle".utf8),
            excludedCredentials: [
                Data("excluded credential".utf8).encodeToBase64UrlSafe(),
                "not base64url",
            ],
            userVerification: .discouraged,
            attestation: .indirect
        )
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task { await passkey.createCredential(window: window, attestationOptions: options) }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleRegistrationRequest())
        #expect(request.relyingPartyIdentifier == options.rp.id)
        #expect(request.challenge == Data("attestation challenge".utf8))
        #expect(request.name == options.user.name)
        #expect(request.userID == Data("user handle".utf8))
        #expect(request.userVerificationPreference == .discouraged)
        #expect(request.attestationPreference == .indirect)
        #expect(request.excludedCredentials?.credentialIDs() == [Data("excluded credential".utf8)])
        #expect(controller.performedOptions == [])
        #expect(controller.delegate === passkey)
        #expect(controller.presentationContextProvider === passkey)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test(arguments: [
        UserVerificationMappingCase(.discouraged, expected: .discouraged),
        UserVerificationMappingCase(.preferred, expected: .preferred),
        UserVerificationMappingCase(.required, expected: .required),
        UserVerificationMappingCase(nil, expected: .required),
    ])
    func `Create credential maps user verification preference`(_ testCase: UserVerificationMappingCase) async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task {
            await passkey.createCredential(
                window: window,
                attestationOptions: attestationOptions(userVerification: testCase.source, attestation: nil)
            )
        }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleRegistrationRequest())
        #expect(request.userVerificationPreference == testCase.expected.authorizationPreference)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test(arguments: [
        AttestationPreferenceMappingCase(.none, expected: .none),
        AttestationPreferenceMappingCase(.direct, expected: .direct),
        AttestationPreferenceMappingCase(.indirect, expected: .indirect),
        AttestationPreferenceMappingCase(.enterprise, expected: .enterprise),
    ])
    func `Create credential maps attestation preference when present`(_ testCase: AttestationPreferenceMappingCase) async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task {
            await passkey.createCredential(
                window: window,
                attestationOptions: attestationOptions(userVerification: nil, attestation: testCase.source)
            )
        }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleRegistrationRequest())
        #expect(request.attestationPreference == testCase.expected.authorizationPreference)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test func `Get credential builds platform assertion request with allow list and immediate option`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let options = assertionOptions(
            challenge: Data("assertion challenge".utf8),
            allowedCredentials: [
                Data("allowed credential".utf8).encodeToBase64UrlSafe(),
                "not base64url",
            ],
            userVerification: .required
        )
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task { await passkey.getCredential(window: window, assertionOptions: options) }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleAssertionRequest())
        #expect(request.relyingPartyIdentifier == options.rpID)
        #expect(request.challenge == Data("assertion challenge".utf8))
        #expect(request.userVerificationPreference == .required)
        #expect(request.allowedCredentials.credentialIDs() == [Data("allowed credential".utf8)])
        #expect(controller.performedOptions == [.preferImmediatelyAvailableCredentials])
        #expect(controller.delegate === passkey)
        #expect(controller.presentationContextProvider === passkey)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test func `Get credential leaves allowed credentials empty when no descriptor can be decoded`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let options = assertionOptions(
            challenge: Data("assertion challenge".utf8),
            allowedCredentials: ["not base64url"],
            userVerification: nil
        )
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task { await passkey.getCredential(window: window, assertionOptions: options) }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleAssertionRequest())
        #expect(request.allowedCredentials.isEmpty)
        #expect(controller.performedOptions == [.preferImmediatelyAvailableCredentials])

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test(arguments: [
        UserVerificationMappingCase(.discouraged, expected: .discouraged),
        UserVerificationMappingCase(.preferred, expected: .preferred),
        UserVerificationMappingCase(.required, expected: .required),
    ])
    func `Get credential maps user verification preference when present`(_ testCase: UserVerificationMappingCase) async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task {
            await passkey.getCredential(window: window, assertionOptions: assertionOptions(userVerification: testCase.source))
        }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleAssertionRequest())
        #expect(request.userVerificationPreference == testCase.expected.authorizationPreference)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test func `Get credential with absent allow list does not restrict credentials`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)
        let window = makeTestWindow()

        let task = Task {
            await passkey.getCredential(window: window, assertionOptions: assertionOptions(allowedCredentials: nil))
        }
        let controller = try await factory.waitForController()

        let request = try #require(controller.authorizationRequests.singleAssertionRequest())
        #expect(request.allowedCredentials.isEmpty)

        controller.complete(with: ASAuthorizationError(.failed))
        _ = await task.value
    }

    @Test func `Invalid attestation challenge and user ID fail before controller creation`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let invalidChallengeFactory = RecordingAuthorizationControllerFactory()
        let invalidChallenge = await makePasskey(factory: invalidChallengeFactory).createCredential(
            window: makeTestWindow(),
            attestationOptions: attestationOptions(challenge: nil, userID: Data("user".utf8), excludedCredentials: nil)
        )

        let invalidUserFactory = RecordingAuthorizationControllerFactory()
        let invalidUserID = await makePasskey(factory: invalidUserFactory).createCredential(
            window: makeTestWindow(),
            attestationOptions: attestationOptions(challenge: Data("challenge".utf8), userID: nil, excludedCredentials: nil)
        )

        #expect(try requireFailure(invalidChallenge).description.contains("Failed to decode challenge data"))
        #expect(try requireFailure(invalidUserID).description.contains("Failed to decode user ID"))
        #expect(invalidChallengeFactory.controllers.isEmpty)
        #expect(invalidUserFactory.controllers.isEmpty)
    }

    @Test func `Invalid assertion challenge fails before controller creation`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let result = await makePasskey(factory: factory).getCredential(
            window: makeTestWindow(),
            assertionOptions: assertionOptions(challenge: nil, allowedCredentials: nil)
        )

        #expect(try requireFailure(result).description.contains("Failed to decode challenge data"))
        #expect(factory.controllers.isEmpty)
    }

    @Test func `Pre-canceled request skips controller attachment and performance and permits a normal retry`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)
        let canceledTask = Task { @MainActor in
            await passkey.getCredential(window: makeTestWindow(), assertionOptions: assertionOptions())
        }
        canceledTask.cancel()

        let reason = try requireCanceled(await canceledTask.value)
        #expect(reason.description == Reason.systemError(details: "Operation canceled").description)
        let preCancelControllers = factory.controllers
        for controller in preCancelControllers {
            #expect(controller.delegate == nil)
            #expect(controller.presentationContextProvider == nil)
            #expect(controller.performedOptions == nil)
        }
        let retryControllerIndex = preCancelControllers.count

        let retryTask = Task { @MainActor in
            await passkey.getCredential(window: makeTestWindow(), assertionOptions: assertionOptions())
        }
        let retryController = try await factory.waitForController(at: retryControllerIndex)
        #expect(retryController.performedOptions != nil)
        retryController.complete(with: ASAuthorizationError(.failed))
        _ = try requireFailure(await retryTask.value)
    }

    @Test func `Second request fails while authorization is active and slot reopens after failure`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)

        let window = makeTestWindow()
        let firstTask = Task { await passkey.createCredential(window: window, attestationOptions: attestationOptions()) }
        let firstController = try await factory.waitForController()

        let second = await passkey.getCredential(window: window, assertionOptions: assertionOptions())

        #expect(try requireFailure(second).description.contains("Another passkey request is already in progress"))
        #expect(factory.controllers.count == 1)

        firstController.complete(with: ASAuthorizationError(.failed))
        _ = try requireFailure(await firstTask.value)

        let retryTask = Task { await passkey.getCredential(window: window, assertionOptions: assertionOptions()) }
        let retryController = try await factory.waitForController(at: 1)
        #expect(retryController.performedOptions != nil)
        retryController.complete(with: ASAuthorizationError(.failed))
        _ = try requireFailure(await retryTask.value)
    }

    @Test func `Task cancellation cancels the active authorization controller and reopens the slot`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory)

        let task = Task { await passkey.createCredential(window: makeTestWindow(), attestationOptions: attestationOptions()) }
        let controller = try await factory.waitForController()

        task.cancel()
        try await controller.waitForCancel()
        controller.complete(with: ASAuthorizationError(.canceled))

        let reason = try requireCanceled(await task.value)
        #expect(reason.description == Reason.userClose(details: "User canceled authorization").description)
        #expect(controller.cancelCallCount == 1)

        let retryTask = Task { await passkey.createCredential(window: makeTestWindow(), attestationOptions: attestationOptions()) }
        let retryController = try await factory.waitForController(at: 1)
        #expect(retryController.performedOptions != nil)
        retryController.complete(with: ASAuthorizationError(.failed))
        _ = try requireFailure(await retryTask.value)
    }

    @Test func `Canceled attestation maps to user close without diagnostics`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics)

        let task = Task { await passkey.createCredential(window: makeTestWindow(), attestationOptions: attestationOptions()) }
        let controller = try await factory.waitForController()
        controller.complete(with: ASAuthorizationError(.canceled))

        let reason = try requireCanceled(await task.value)
        #expect(reason.description == Reason.userClose(details: "User canceled authorization").description)
        #expect(diagnostics.rpIds.isEmpty)
    }

    @Test func `Immediate canceled assertion maps to no credential without diagnostics`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics)

        let task = Task { await passkey.getCredential(window: makeTestWindow(), assertionOptions: assertionOptions()) }
        let controller = try await factory.waitForController()
        controller.complete(with: ASAuthorizationError(.canceled))

        let failure = try requireNoCredentialFailure(await task.value)
        #expect(failure.message == "No Credentials Available")
        #expect(failure.identifier == .noCredential)
        #expect(diagnostics.rpIds.isEmpty)
    }

    @Test func `Delayed canceled assertion maps to user close without diagnostics`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let start = ContinuousClock().now
        var now = start
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics, now: { now })

        let task = Task { await passkey.getCredential(window: makeTestWindow(), assertionOptions: assertionOptions()) }
        let controller = try await factory.waitForController()
        now = start + .milliseconds(650)
        controller.complete(with: ASAuthorizationError(.canceled))

        let reason = try requireCanceled(await task.value)
        #expect(reason.description == Reason.userClose(details: "User canceled authorization").description)
        #expect(diagnostics.rpIds.isEmpty)
    }

    @Test func `Authorization failures map identifiers and trigger diagnostics for request RP ID`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let createDiagnostics = RecordingPasskeyDiagnostics()
        let createFactory = RecordingAuthorizationControllerFactory()
        let createOptions = attestationOptions(rpID: "create.example.test")
        let createPasskey = makePasskey(factory: createFactory, diagnostics: createDiagnostics)
        let createTask = Task { await createPasskey.createCredential(window: makeTestWindow(), attestationOptions: createOptions) }
        let createController = try await createFactory.waitForController()
        createController.complete(with: ASAuthorizationError(.notHandled))

        let createFailure = try requireFailure(await createTask.value)
        #expect(createFailure.identifier == .notHandled)
        #expect(createDiagnostics.rpIds == ["create.example.test"])

        let getDiagnostics = RecordingPasskeyDiagnostics()
        let getFactory = RecordingAuthorizationControllerFactory()
        let getOptions = assertionOptions(rpID: "get.example.test")
        let getPasskey = makePasskey(factory: getFactory, diagnostics: getDiagnostics)
        let getTask = Task { await getPasskey.getCredential(window: makeTestWindow(), assertionOptions: getOptions) }
        let getController = try await getFactory.waitForController()
        getController.complete(with: ASAuthorizationError(.failed))

        let getFailure = try requireFailure(await getTask.value)
        #expect(getFailure.identifier == .failed)
        #expect(getDiagnostics.rpIds == ["get.example.test"])
    }

    @Test(arguments: [
        ErrorIdentifierMappingCase(1002, expected: .invalidResponse),
        ErrorIdentifierMappingCase(1003, expected: .notHandled),
        ErrorIdentifierMappingCase(1004, expected: .failed),
        ErrorIdentifierMappingCase(1005, expected: .notInteractive),
        ErrorIdentifierMappingCase(1006, expected: .matchedExcludedCredential),
        ErrorIdentifierMappingCase(1007, expected: .credentialImport),
        ErrorIdentifierMappingCase(1008, expected: .credentialExport),
        ErrorIdentifierMappingCase(1009, expected: .preferSignInWithApple),
        ErrorIdentifierMappingCase(1010, expected: .deviceNotConfiguredForPasskeyCreation),
        ErrorIdentifierMappingCase(1999, expected: .code(1999)),
    ])
    func `NSError authorization domain codes map to stable identifiers`(_ testCase: ErrorIdentifierMappingCase) async throws {
        guard #available(iOS 16.0, *) else { return }

        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics)
        let rpID = "error-\(testCase.rawCode).example.test"

        let task = Task { await passkey.createCredential(window: makeTestWindow(), attestationOptions: attestationOptions(rpID: rpID)) }
        let controller = try await factory.waitForController()
        controller.complete(with: NSError(domain: ASAuthorizationErrorDomain, code: testCase.rawCode))

        let failure = try requireFailure(await task.value)
        #expect(failure.identifier == testCase.expected)
        #expect(diagnostics.rpIds == [rpID])
    }

    @Test func `NSError canceled authorization maps to user close without diagnostics`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics)

        let task = Task { await passkey.createCredential(window: makeTestWindow(), attestationOptions: attestationOptions()) }
        let controller = try await factory.waitForController()
        controller.complete(with: NSError(domain: ASAuthorizationErrorDomain, code: 1001))

        let reason = try requireCanceled(await task.value)
        #expect(reason.description == Reason.userClose(details: "User canceled authorization").description)
        #expect(diagnostics.rpIds.isEmpty)
    }

    @Test func `Non authorization errors keep unknown identifier and trigger diagnostics`() async throws {
        guard #available(iOS 16.0, *) else { return }

        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics)

        let task = Task {
            await passkey.createCredential(
                window: makeTestWindow(),
                attestationOptions: attestationOptions(rpID: "generic-error.example.test")
            )
        }
        let controller = try await factory.waitForController()
        controller.complete(with: NSError(domain: "example.test", code: 42))

        let failure = try requireFailure(await task.value)
        #expect(failure.identifier == nil)
        #expect(diagnostics.rpIds == ["generic-error.example.test"])
    }

    @Test(arguments: [false, true])
    func `Failure warning preserves native error details and localized cause`(_ authorizationError: Bool) async throws {
        guard #available(iOS 16.0, *) else { return }

        let error = NSError(
            domain: authorizationError ? ASAuthorizationErrorDomain : "example.test",
            code: authorizationError ? 1004 : 42,
            userInfo: [NSLocalizedDescriptionKey: "Original provider failure"]
        )
        let sink = LogCapture()
        let diagnostics = RecordingPasskeyDiagnostics()
        let factory = RecordingAuthorizationControllerFactory()
        let passkey = makePasskey(factory: factory, diagnostics: diagnostics, logger: testLogRouter(sink: sink))
        let task = Task { await passkey.createCredential(window: makeTestWindow(), attestationOptions: attestationOptions()) }
        let controller = try await factory.waitForController()
        controller.complete(with: error)

        let failure = try requireFailure(await task.value)
        let warning = try #require(sink.entries.first { $0.level == .warn })
        #expect(warning.message == "Authorization failed (domain=\(error.domain), code=\(error.code))")
        #expect(warning.hasCause)
        #expect(warning.causeDescription == error.localizedDescription)
        #expect(failure.identifier == (authorizationError ? .failed : nil))
        guard case .general(let message, let cause, _) = failure else {
            Issue.record("Expected the original general passkey failure")
            return
        }
        #expect(message == error.localizedDescription)
        #expect((cause as NSError?) === error)
        #expect(diagnostics.rpIds == ["login.example.test"])
    }

    @available(iOS 16.0, *)
    private func makeAuthorizationController() -> ASAuthorizationController {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.test")
        let request = provider.createCredentialAssertionRequest(challenge: Data("challenge".utf8))
        return ASAuthorizationController(authorizationRequests: [request])
    }
}

@available(iOS 16.0, *)
@MainActor
private func makePasskey(
    factory: RecordingAuthorizationControllerFactory = RecordingAuthorizationControllerFactory(),
    diagnostics: RecordingPasskeyDiagnostics = RecordingPasskeyDiagnostics(),
    logger: OwnIDLogRouter? = nil,
    now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now }
) -> PasskeyImpl {
    PasskeyImpl(
        logger: logger,
        diagnosticsProvider: { diagnostics },
        now: now,
        authorizationControllerFactory: { factory.makeController(authorizationRequests: $0) }
    )
}

@MainActor
private func makeTestWindow() -> UIWindow {
    UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
}

@available(iOS 16.0, *)
private func attestationOptions(
    rpID: String = "login.example.test",
    challenge: Data? = Data("attestation challenge".utf8),
    userID: Data? = Data("user handle".utf8),
    excludedCredentials: [String]? = [Data("excluded credential".utf8).encodeToBase64UrlSafe()],
    userVerification: UserVerification? = .required,
    attestation: AttestationConveyancePreference? = .direct
) -> AttestationOptions {
    AttestationOptions(
        rp: .init(id: rpID, name: "Example RP"),
        user: .init(
            id: userID?.encodeToBase64UrlSafe() ?? "not base64url",
            name: "person@example.test",
            displayName: "Test Person"
        ),
        challenge: ChallengeID(challenge?.encodeToBase64UrlSafe() ?? "not base64url"),
        pubKeyCredParams: [.init(type: .publicKey, alg: .ES256)],
        attestation: attestation,
        authenticatorSelection: .init(authenticatorAttachment: .platform, userVerification: userVerification, residentKey: .preferred),
        timeout: Timeout(milliseconds: 10_000),
        excludeCredentials: excludedCredentials?.map { PublicKeyCredentialDescriptor(id: $0, type: .publicKey, transports: [.internal]) }
    )
}

@available(iOS 16.0, *)
private func assertionOptions(
    rpID: String = "login.example.test",
    challenge: Data? = Data("assertion challenge".utf8),
    allowedCredentials: [String]? = [Data("allowed credential".utf8).encodeToBase64UrlSafe()],
    userVerification: UserVerification? = .preferred
) -> AssertionOptions {
    AssertionOptions(
        challenge: ChallengeID(challenge?.encodeToBase64UrlSafe() ?? "not base64url"),
        rpID: rpID,
        allowCredentials: allowedCredentials?.map { PublicKeyCredentialDescriptor(id: $0, type: .publicKey, transports: [.internal]) },
        userVerification: userVerification,
        timeout: Timeout(milliseconds: 10_000)
    )
}

private func requireFailure<R: Sendable>(
    _ result: PasskeyResult<R>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> PasskeyResult<R>.Error {
    switch result {
    case .failure(let error):
        return error
    case .success(let value):
        return try #require(nil as PasskeyResult<R>.Error?, "Expected failure, got success: \(value)", sourceLocation: sourceLocation)
    case .canceled(let reason):
        return try #require(nil as PasskeyResult<R>.Error?, "Expected failure, got cancellation: \(reason)", sourceLocation: sourceLocation)
    }
}

private func requireCanceled<R: Sendable>(
    _ result: PasskeyResult<R>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> Reason {
    switch result {
    case .canceled(let reason):
        return reason
    case .success(let value):
        return try #require(nil as Reason?, "Expected cancellation, got success: \(value)", sourceLocation: sourceLocation)
    case .failure(let error):
        return try #require(nil as Reason?, "Expected cancellation, got failure: \(error)", sourceLocation: sourceLocation)
    }
}

private func requireNoCredentialFailure<R: Sendable>(
    _ result: PasskeyResult<R>,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) throws -> NoCredentialFailure {
    let failure = try requireFailure(result, sourceLocation: sourceLocation)
    guard case .passkeysNoCredential(let message, _, let identifier) = failure else {
        return try #require(
            nil as NoCredentialFailure?,
            "Expected no-credential failure, got \(failure)",
            sourceLocation: sourceLocation
        )
    }
    return NoCredentialFailure(message: message, identifier: identifier)
}

private struct NoCredentialFailure: Sendable {
    let message: String
    let identifier: PasskeyAuthorizationErrorIdentifier?
}

struct UserVerificationMappingCase: Sendable, CustomTestStringConvertible {
    let source: UserVerification?
    let expected: ExpectedUserVerificationPreference

    init(_ source: UserVerification?, expected: ExpectedUserVerificationPreference) {
        self.source = source
        self.expected = expected
    }

    var testDescription: String {
        "\(source.map(\.rawValue) ?? "nil")->\(expected.rawValue)"
    }
}

struct AttestationPreferenceMappingCase: Sendable, CustomTestStringConvertible {
    let source: AttestationConveyancePreference
    let expected: ExpectedAttestationPreference

    init(_ source: AttestationConveyancePreference, expected: ExpectedAttestationPreference) {
        self.source = source
        self.expected = expected
    }

    var testDescription: String {
        "\(source.rawValue)->\(expected.rawValue)"
    }
}

struct ErrorIdentifierMappingCase: Sendable, CustomTestStringConvertible {
    let rawCode: Int
    let expected: PasskeyAuthorizationErrorIdentifier

    init(_ rawCode: Int, expected: PasskeyAuthorizationErrorIdentifier) {
        self.rawCode = rawCode
        self.expected = expected
    }

    var testDescription: String {
        "\(rawCode)->\(expected.value)"
    }
}

enum ExpectedUserVerificationPreference: String, Sendable {
    case discouraged
    case preferred
    case required

    @available(iOS 15.0, *)
    var authorizationPreference: ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch self {
        case .discouraged: return .discouraged
        case .preferred: return .preferred
        case .required: return .required
        }
    }
}

enum ExpectedAttestationPreference: String, Sendable {
    case none
    case direct
    case indirect
    case enterprise

    @available(iOS 15.0, *)
    var authorizationPreference: ASAuthorizationPublicKeyCredentialAttestationKind {
        switch self {
        case .none: return .none
        case .direct: return .direct
        case .indirect: return .indirect
        case .enterprise: return .enterprise
        }
    }
}

@available(iOS 16.0, *)
@MainActor
private final class RecordingAuthorizationControllerFactory {
    private(set) var controllers: [RecordingPasskeyAuthorizationController] = []
    private var controllerWaiters: [Int: [CheckedContinuation<RecordingPasskeyAuthorizationController, Never>]] = [:]

    func makeController(authorizationRequests: [ASAuthorizationRequest]) -> any PasskeyAuthorizationController {
        let controller = RecordingPasskeyAuthorizationController(authorizationRequests: authorizationRequests)
        controllers.append(controller)
        for (index, waiters) in controllerWaiters where controllers.indices.contains(index) {
            controllerWaiters.removeValue(forKey: index)
            for waiter in waiters {
                waiter.resume(returning: controllers[index])
            }
        }
        return controller
    }

    func waitForController(at index: Int = 0) async throws -> RecordingPasskeyAuthorizationController {
        try await withTestTimeout("passkey authorization controller", seconds: 2) {
            await self.controller(at: index)
        }
    }

    private func controller(at index: Int) async -> RecordingPasskeyAuthorizationController {
        if controllers.indices.contains(index) {
            return controllers[index]
        }

        return await withCheckedContinuation { continuation in
            if controllers.indices.contains(index) {
                continuation.resume(returning: controllers[index])
            } else {
                controllerWaiters[index, default: []].append(continuation)
            }
        }
    }
}

@available(iOS 16.0, *)
@MainActor
private final class RecordingPasskeyAuthorizationController: PasskeyAuthorizationController {
    let authorizationRequests: [ASAuthorizationRequest]
    weak var delegate: (any ASAuthorizationControllerDelegate)?
    weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?

    private(set) var performedOptions: ASAuthorizationController.RequestOptions?
    private(set) var cancelCallCount = 0
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []

    init(authorizationRequests: [ASAuthorizationRequest]) {
        self.authorizationRequests = authorizationRequests
    }

    func performRequests(options: ASAuthorizationController.RequestOptions) {
        performedOptions = options
    }

    func cancel() {
        cancelCallCount += 1
        let waiters = cancelWaiters
        cancelWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func complete(with error: any Error) {
        let callbackController = ASAuthorizationController(authorizationRequests: authorizationRequests)
        delegate?.authorizationController?(controller: callbackController, didCompleteWithError: error)
    }

    func waitForCancel() async throws {
        try await withTestTimeout("passkey authorization cancel", seconds: 2) {
            await self.firstCancel()
        }
    }

    private func firstCancel() async {
        if cancelCallCount > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            if cancelCallCount > 0 {
                continuation.resume()
            } else {
                cancelWaiters.append(continuation)
            }
        }
    }
}

@available(iOS 16.0, *)
private final class RecordingPasskeyDiagnostics: PasskeyDiagnostics, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var rpIds: [String] {
        lock.withLock { storage }
    }

    func verify(rpId: String) {
        lock.withLock { storage.append(rpId) }
    }
}

@available(iOS 16.0, *)
extension Array where Element == ASAuthorizationRequest {
    fileprivate func singleRegistrationRequest() -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest? {
        guard count == 1 else { return nil }
        return first as? ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest
    }

    fileprivate func singleAssertionRequest() -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest? {
        guard count == 1 else { return nil }
        return first as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest
    }
}

@available(iOS 16.0, *)
extension Array where Element == ASAuthorizationPlatformPublicKeyCredentialDescriptor {
    fileprivate func credentialIDs() -> [Data] {
        map { ($0 as ASAuthorizationPublicKeyCredentialDescriptor).credentialID }
    }
}
