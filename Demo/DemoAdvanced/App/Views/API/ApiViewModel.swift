import Combine
import Foundation
@_spi(OwnIDInternal) import OwnIDCore

@MainActor
final class ApiViewModel: ObservableObject {
    enum Mode: String, CaseIterable {
        case loginID = "Login ID"
        case accessToken = "Access Token"
    }

    struct VerificationScreenState {
        var challenge: VerificationChallenge? = nil
        var status: String? = nil
        var resend: () -> Void = {}
        var cancel: () -> Void = {}
        var completeWithCode: (String) -> Void = { _ in }
        var proofToken: ProofToken? = nil
        var accessTokenResult: AccessToken? = nil
        var enrollResult: String? = nil

        var isActive: Bool {
            challenge != nil || proofToken != nil
        }
    }

    struct PasskeyCreateState {
        var attestationOptions: AttestationOptions? = nil
        var status: String? = nil
        var createPasskey: () -> Void = {}
        var cancelPasskey: () -> Void = {}
        var attestationResult: AttestationResult? = nil
        var verifyAttestation: (AttestationResult) -> Void = { _ in }
        var attestationResponse: AttestationResponse? = nil
        var enrollResult: String? = nil

        var isActive: Bool {
            attestationOptions != nil || attestationResult != nil || attestationResponse != nil
        }
    }

    struct PasskeyAssertionsState {
        var assertionOptions: AssertionOptions? = nil
        var status: String? = nil
        var runAssertion: () -> Void = {}
        var cancelAssertion: () -> Void = {}
        var assertionResult: AssertionResult? = nil
        var verifyAssertion: (AssertionResult) -> Void = { _ in }
        var accessTokenResult: AccessToken? = nil

        var isActive: Bool {
            assertionOptions != nil || assertionResult != nil
        }
    }

    struct DiscoverState {
        var discoverResponse: LoginResponse? = nil
        var discoverStatus: String? = nil

        var hasState: Bool {
            discoverResponse != nil || discoverStatus != nil
        }
    }

    struct LoginState {
        var loginResponse: LoginResponse? = nil
        var loginStatus: String? = nil

        var hasState: Bool {
            loginResponse != nil || loginStatus != nil
        }
    }

    struct OIDCState {
        var provider: SocialProviderID = .apple
        var challenge: SocialChallenge? = nil
        var status: String? = nil
        var authorize: () -> Void = {}
        var cancel: () -> Void = {}
        var result: AccessTokenWithUserInfo? = nil

        var isActive: Bool {
            challenge != nil
        }

        var hasState: Bool {
            challenge != nil || status != nil || result != nil
        }
    }

    struct ScreenState {
        var mode: Mode = .loginID
        var loginID = ""
        var loginIDType: OwnIDCore.LoginIDType = .email
        var accessToken: AccessToken? = nil

        var canStartOperation: Bool {
            if mode == .accessToken {
                accessToken != nil
            } else {
                !isLoginIDBlank
            }
        }

        var isLoginIDBlank: Bool {
            loginID.allSatisfy(\.isWhitespace)
        }
    }

    @Published var screenState = ScreenState()
    @Published var verificationState = VerificationScreenState()
    @Published var passkeyCreateState = PasskeyCreateState()
    @Published var passkeyAssertionsState = PasskeyAssertionsState()
    @Published var discoverState = DiscoverState()
    @Published var loginState = LoginState()
    @Published var oidcState = OIDCState()

    private let ownID = OwnID.instance() as! any OwnIDFullInstance

    func onLoginIDChanged(_ value: String) {
        guard screenState.loginID != value else { return }
        screenState.loginID = value
    }

    func onLoginIDTypeSelected(_ type: OwnIDCore.LoginIDType) {
        guard screenState.loginIDType != type else { return }
        screenState.loginIDType = type
    }

    func onModeSelected(_ mode: Mode) {
        guard screenState.mode != mode, mode != .accessToken || screenState.accessToken != nil else { return }
        screenState.mode = mode
    }

    func resetVerificationState() {
        verificationState = VerificationScreenState()
    }

    func resetPasskeyCreateState() {
        passkeyCreateState = PasskeyCreateState()
    }

    func resetPasskeyAssertionsState() {
        passkeyAssertionsState = PasskeyAssertionsState()
    }

    func resetDiscoverState() {
        discoverState = DiscoverState()
    }

    func resetLoginState() {
        loginState = LoginState()
    }

    func onOIDCProviderSelected(_ provider: SocialProviderID) {
        guard oidcState.provider != provider else { return }
        oidcState.provider = provider
    }

    func resetOIDCState() {
        let provider = oidcState.provider
        oidcState = OIDCState(provider: provider)
    }

    func startVerificationChallenge() {
        resetVerificationState()

        Task { @MainActor in
            let api = ownID.api.withContext { context in
                if screenState.mode == .accessToken {
                    context.authz = screenState.accessToken.map { .fromToken($0) }
                } else {
                    context.authz = .start(LoginID(id: screenState.loginID, type: screenState.loginIDType))
                }
            }

            switch screenState.loginIDType {
            case .email:
                await api.verifications.email.start()
                    .onSuccess { controller in
                        verificationState = VerificationScreenState(
                            challenge: controller.challenge,
                            resend: { [self] in
                                Task { @MainActor in
                                    await controller.resend()
                                        .onSuccess {
                                            verificationState.status = "Resend succeeded"
                                            verificationState.enrollResult = nil
                                        }
                                        .onError { error in verificationState.status = String(describing: error) }
                                }
                            },
                            cancel: { [self] in
                                Task { @MainActor in
                                    await controller.cancel(reason: .userClose())
                                        .onSuccess { verificationState = VerificationScreenState(status: "Verification canceled") }
                                        .onError { error in verificationState.status = String(describing: error) }
                                }
                            },
                            completeWithCode: { [self] code in
                                Task { @MainActor in
                                    await controller.completeWithCode(code: code)
                                        .onSuccess { token in
                                            switch token {
                                            case .accessToken(let accessToken):
                                                screenState.accessToken = accessToken
                                                verificationState = VerificationScreenState(accessTokenResult: accessToken)
                                            case .proofToken(let proofToken):
                                                verificationState = VerificationScreenState(proofToken: proofToken)
                                            }
                                        }
                                        .onError { error in verificationState.status = String(describing: error) }
                                }
                            }
                        )
                    }
                    .onError { error in verificationState = VerificationScreenState(status: String(describing: error)) }

            case .phoneNumber:
                await api.verifications.phone.start()
                    .onSuccess { controller in
                        verificationState = VerificationScreenState(
                            challenge: controller.challenge,
                            resend: { [self] in
                                Task { @MainActor in
                                    await controller.resend()
                                        .onSuccess {
                                            verificationState.status = "Resend succeeded"
                                            verificationState.enrollResult = nil
                                        }
                                        .onError { error in verificationState.status = String(describing: error) }
                                }
                            },
                            cancel: { [self] in
                                Task { @MainActor in
                                    await controller.cancel(reason: .userClose())
                                        .onSuccess { verificationState = VerificationScreenState(status: "Verification canceled") }
                                        .onError { error in verificationState.status = String(describing: error) }
                                }
                            },
                            completeWithCode: { [self] code in
                                Task { @MainActor in
                                    await controller.completeWithCode(code: code)
                                        .onSuccess { token in
                                            switch token {
                                            case .accessToken(let accessToken):
                                                screenState.accessToken = accessToken
                                                verificationState = VerificationScreenState(accessTokenResult: accessToken)
                                            case .proofToken(let proofToken):
                                                verificationState = VerificationScreenState(proofToken: proofToken)
                                            }
                                        }
                                        .onError { error in verificationState.status = String(describing: error) }
                                }
                            }
                        )
                    }
                    .onError { error in verificationState = VerificationScreenState(status: String(describing: error)) }

            default:
                preconditionFailure("Unsupported verification login ID type: \(screenState.loginIDType)")
            }
        }
    }

    func startVerificationEnrollment() {
        guard let proofToken = verificationState.proofToken, let accessToken = screenState.accessToken else { return }

        verificationState.enrollResult = nil

        Task { @MainActor in
            let api = ownID.api.withContext { context in
                context.authz = .fromToken(accessToken)
            }

            switch screenState.loginIDType {
            case .email:
                await api.enroll.email.start(params: EmailEnrollAPIParams(proofToken: proofToken))
                    .onSuccess {
                        verificationState = VerificationScreenState(enrollResult: "Verification enrollment succeeded")
                    }
                    .onError { error in verificationState.enrollResult = String(describing: error) }

            case .phoneNumber:
                await api.enroll.phone.start(params: PhoneEnrollAPIParams(proofToken: proofToken))
                    .onSuccess {
                        verificationState = VerificationScreenState(enrollResult: "Verification enrollment succeeded")
                    }
                    .onError { error in verificationState.enrollResult = String(describing: error) }

            default:
                preconditionFailure("Unsupported verification login ID type: \(screenState.loginIDType)")
            }
        }
    }

    func startPasskeyCreateChallenge() {
        resetPasskeyCreateState()

        Task { @MainActor in
            let api = ownID.api.withContext { context in
                if screenState.mode == .accessToken {
                    context.authz = screenState.accessToken.map { .fromToken($0) }
                } else {
                    context.authz = .start(LoginID(id: screenState.loginID, type: screenState.loginIDType))
                }
            }

            await api.passkeys.attestation.start()
                .onSuccess { controller in
                    passkeyCreateState = PasskeyCreateState(
                        attestationOptions: controller.attestationOptions,
                        createPasskey: { [self] in
                            Task { @MainActor in
                                let result: PasskeyResult<AttestationResult>
                                do {
                                    let container = OwnID.getInstanceContainer()!
                                    let passkeyUI = try container.getOrThrow(type: (any PasskeyAttestationUI).self)
                                    result = await passkeyUI.createCredential(options: controller.attestationOptions)
                                } catch {
                                    result = .failure(.general(error.localizedDescription, error))
                                }

                                switch result {
                                case .success(let attestationResult):
                                    passkeyCreateState.status = nil
                                    passkeyCreateState.attestationResult = attestationResult
                                case .canceled(let reason):
                                    passkeyCreateState.status = String(describing: reason)
                                    passkeyCreateState.attestationResult = nil
                                case .failure(let error):
                                    passkeyCreateState.status = String(describing: error)
                                    passkeyCreateState.attestationResult = nil
                                }
                            }
                        },
                        cancelPasskey: { [self] in
                            Task { @MainActor in
                                await controller.cancel(reason: .userClose())
                                    .onSuccess { passkeyCreateState = PasskeyCreateState(status: "Passkey create canceled") }
                                    .onError { error in passkeyCreateState.status = String(describing: error) }
                            }
                        },
                        verifyAttestation: { [self] attestationResult in
                            Task { @MainActor in
                                await controller.verify(attestationResult: attestationResult)
                                    .onSuccess { response in passkeyCreateState = PasskeyCreateState(attestationResponse: response) }
                                    .onError { error in passkeyCreateState.status = String(describing: error) }
                            }
                        }
                    )
                }
                .onError { error in passkeyCreateState = PasskeyCreateState(status: String(describing: error)) }
        }
    }

    func startPasskeyEnrollment() {
        guard let proofToken = passkeyCreateState.attestationResponse?.proofToken, let accessToken = screenState.accessToken else { return }

        passkeyCreateState.enrollResult = nil

        Task { @MainActor in
            let api = ownID.api.withContext { context in
                context.authz = .fromToken(accessToken)
            }

            await api.enroll.passkey.start(params: PasskeyEnrollAPIParams(proofToken: proofToken))
                .onSuccess { passkeyCreateState = PasskeyCreateState(enrollResult: "Passkey enroll succeeded") }
                .onError { error in passkeyCreateState.enrollResult = String(describing: error) }
        }
    }

    func startPasskeyAssertionChallenge() {
        resetPasskeyAssertionsState()

        Task { @MainActor in
            let params: PasskeyAssertionAPIParams
            if screenState.mode == .accessToken {
                params = PasskeyAssertionAPIParams(accessToken: screenState.accessToken)
            } else {
                params = PasskeyAssertionAPIParams(
                    loginID: screenState.isLoginIDBlank ? nil : LoginID(id: screenState.loginID, type: screenState.loginIDType)
                )
            }

            await ownID.api.passkeys.assertion.start(params: params)
                .onSuccess { controller in
                    passkeyAssertionsState = PasskeyAssertionsState(
                        assertionOptions: controller.assertionOptions,
                        runAssertion: { [self] in
                            Task { @MainActor in
                                let result: PasskeyResult<AssertionResult>
                                do {
                                    let container = OwnID.getInstanceContainer()!
                                    let passkeyUI = try container.getOrThrow(type: (any PasskeyAssertionUI).self)
                                    result = await passkeyUI.getCredential(options: controller.assertionOptions)
                                } catch {
                                    result = .failure(.general(error.localizedDescription, error))
                                }

                                switch result {
                                case .success(let assertionResult):
                                    passkeyAssertionsState.status = nil
                                    passkeyAssertionsState.assertionResult = assertionResult
                                case .canceled(let reason):
                                    passkeyAssertionsState.status = String(describing: reason)
                                    passkeyAssertionsState.assertionResult = nil
                                case .failure(let error):
                                    passkeyAssertionsState.status = String(describing: error)
                                    passkeyAssertionsState.assertionResult = nil
                                }
                            }
                        },
                        cancelAssertion: { [self] in
                            Task { @MainActor in
                                await controller.cancel(reason: .userClose())
                                    .onSuccess { passkeyAssertionsState = PasskeyAssertionsState(status: "Assertion canceled") }
                                    .onError { error in passkeyAssertionsState.status = String(describing: error) }
                            }
                        },
                        verifyAssertion: { [self] assertionResult in
                            Task { @MainActor in
                                await controller.verify(assertionResult: assertionResult)
                                    .onSuccess { accessToken in
                                        screenState.accessToken = accessToken
                                        passkeyAssertionsState = PasskeyAssertionsState(accessTokenResult: accessToken)
                                    }
                                    .onError { error in passkeyAssertionsState.status = String(describing: error) }
                            }
                        }
                    )
                }
                .onError { error in passkeyAssertionsState = PasskeyAssertionsState(status: String(describing: error)) }
        }
    }

    func startDiscoverLoginDiscover() {
        resetDiscoverState()

        Task { @MainActor in
            let api = ownID.api.withContext { context in
                context.authz = .start(LoginID(id: screenState.loginID, type: screenState.loginIDType))
            }

            await api.auth.discover.start()
                .onSuccess { response in
                    if case .success(let success) = response {
                        screenState.accessToken = success.accessToken
                    }
                    discoverState = DiscoverState(discoverResponse: response)
                }
                .onError { error in discoverState = DiscoverState(discoverStatus: String(describing: error)) }
        }
    }

    func startDiscoverLoginLogin() {
        guard let accessToken = screenState.accessToken else { return }
        resetLoginState()

        Task { @MainActor in
            let api = ownID.api.withContext { context in
                context.authz = .fromToken(accessToken)
            }

            await api.auth.login.start()
                .onSuccess { response in
                    if case .success(let success) = response {
                        screenState.accessToken = success.accessToken
                    }
                    loginState = LoginState(loginResponse: response)
                }
                .onError { error in loginState = LoginState(loginStatus: String(describing: error)) }
        }
    }

    func startOIDCChallenge() {
        resetOIDCState()

        Task { @MainActor in
            let provider = oidcState.provider
            let api = ownID.api.withContext { context in
                if screenState.mode == .accessToken {
                    context.authz = screenState.accessToken.map { .fromToken($0) }
                } else {
                    context.authz = nil
                }
            }

            await api.oidc.start(params: OIDCAPIParams(provider: provider))
                .onSuccess { controller in
                    oidcState = OIDCState(
                        provider: provider,
                        challenge: controller.challenge,
                        authorize: { [self] in
                            Task { @MainActor in
                                let socialResult: SocialResult
                                do {
                                    let container = OwnID.getInstanceContainer()!
                                    switch provider {
                                    case .apple:
                                        let appleUI = try container.getOrThrow(type: (any SignInWithAppleUI).self)
                                        socialResult = await appleUI.signIn(
                                            clientID: controller.challenge.clientID,
                                            nonce: controller.challenge.challengeID.value,
                                            window: nil
                                        )
                                    case .google:
                                        let googleUI = try container.getOrThrow(type: (any SignInWithGoogleUI).self)
                                        socialResult = await googleUI.signIn(
                                            clientID: controller.challenge.clientID,
                                            nonce: controller.challenge.challengeID.value,
                                            window: nil
                                        )
                                    }
                                } catch {
                                    socialResult = .fail(error: .general(error.localizedDescription, error))
                                }

                                switch socialResult {
                                case .success(_, let idToken):
                                    await controller.completeWithToken(idToken: idToken)
                                        .onSuccess { result in
                                            screenState.loginID = result.loginID.id
                                            screenState.loginIDType = result.loginID.type
                                            screenState.accessToken = result.accessToken
                                            oidcState = OIDCState(provider: provider, result: result)
                                        }
                                        .onError { error in
                                            oidcState.status = String(describing: error)
                                        }
                                case .canceled(let reason):
                                    oidcState.status = String(describing: reason)
                                case .fail(let error):
                                    oidcState.status = String(describing: error)
                                }
                            }
                        },
                        cancel: { [self] in
                            Task { @MainActor in
                                await controller.cancel(reason: .userClose())
                                    .onSuccess { oidcState = OIDCState(provider: provider, status: "OIDC canceled") }
                                    .onError { error in oidcState.status = String(describing: error) }
                            }
                        }
                    )
                }
                .onError { error in
                    oidcState = OIDCState(provider: provider, status: String(describing: error))
                }
        }
    }
}
