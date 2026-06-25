import Combine
import Foundation
@_spi(OwnIDInternal) import OwnIDCore
import OwnIDSwiftUI

@MainActor
final class OperationViewModel: ObservableObject {
    enum UIMode: String, CaseIterable {
        case `default`
        case dialog
        case embedded

        var title: String {
            switch self {
            case .default: return "Default"
            case .dialog: return "Dialog"
            case .embedded: return "Embedded"
            }
        }
    }

    struct ScreenState {
        var loginID = ""
        var loginIDType: OwnIDCore.LoginIDType? = nil
        var verificationLoginIDType: OwnIDCore.LoginIDType = .email
        var accessToken: AccessToken? = nil
        var useAccessToken = false
        var attestationResponse: AttestationResponse? = nil
        var uiMode: UIMode = .default

        var canStartOperation: Bool {
            if useAccessToken {
                accessToken != nil
            } else {
                !isBlank(loginID)
            }
        }

        var canStartDiscoverOperation: Bool {
            !isBlank(loginID)
        }

        var isLoginIDBlank: Bool {
            isBlank(loginID)
        }

        private func isBlank(_ value: String) -> Bool {
            value.allSatisfy(\.isWhitespace)
        }
    }

    @Published var screenState = ScreenState()
    @Published var loginIDOperationUIController: OwnIDOperationUIController<LoginID, LoginIDCollectOperationFailure>?
    @Published var emailVerificationOperationUIController:
        OwnIDOperationUIController<AccessOrProofToken, EmailVerificationOperationFailure>?
    @Published var phoneVerificationOperationUIController:
        OwnIDOperationUIController<AccessOrProofToken, PhoneVerificationOperationFailure>?

    private let ownID = OwnID.instance() as! any OwnIDFullInstance

    let log = LogStore()

    func onLoginIDChanged(_ value: String) {
        guard screenState.loginID != value else { return }
        screenState.loginID = value
    }

    func onLoginIDTypeSelected(_ type: OwnIDCore.LoginIDType?) {
        guard screenState.loginIDType != type else { return }
        screenState.loginIDType = type
    }

    func onVerificationLoginIDTypeSelected(_ type: OwnIDCore.LoginIDType) {
        guard screenState.verificationLoginIDType != type else { return }
        screenState.verificationLoginIDType = type
    }

    func onUseAccessTokenChanged(_ useAccessToken: Bool) {
        guard screenState.accessToken != nil, screenState.useAccessToken != useAccessToken else { return }
        screenState.useAccessToken = useAccessToken
    }

    func onUIModeSelected(_ mode: UIMode) {
        guard screenState.uiMode != mode else { return }
        clearOperationControllers()
        screenState.uiMode = mode
    }

    func startLoginIdCollectOperation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let uiMode = screenState.uiMode
            clearOperationControllers()
            log.add("Login ID Collect started")

            let loginIDCollectOperation = ownID.ops
                .withContext { context in
                    context.authz =
                        self.screenState.isLoginIDBlank
                        ? nil
                        : .start(self.screenState.loginID, type: self.screenState.loginIDType)
                }
                .loginID.collect

            switch uiMode {
            case .default:
                await loginIDCollectOperation.start()
                    .whenSettled()
                    .onSuccess { loginID in
                        self.log.add("Login ID Collect succeeded: \(loginID)")
                    }
                    .onCanceled { reason in
                        self.log.add("Login ID Collect canceled: \(reason)")
                    }
                    .onError { error in
                        self.log.add("Login ID Collect failed: \(error)")
                    }

            case .dialog, .embedded:
                let controller = loginIDCollectOperation.useAppHostedComponent.start()
                loginIDOperationUIController = controller

                await controller.whenSettled()
                    .onSuccess { loginID in
                        self.log.add("Login ID Collect succeeded: \(loginID)")
                    }
                    .onCanceled { reason in
                        self.log.add("Login ID Collect canceled: \(reason)")
                    }
                    .onError { error in
                        self.log.add("Login ID Collect failed: \(error)")
                    }

                if self.loginIDOperationUIController === controller {
                    self.loginIDOperationUIController = nil
                }
            }
        }
    }

    func startVerificationOperation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let uiMode = screenState.uiMode
            clearOperationControllers()

            let operations = ownID.ops
                .withContext { context in
                    if self.screenState.useAccessToken {
                        context.authz = self.screenState.accessToken.map { .fromToken($0) }
                    } else {
                        context.authz =
                            self.screenState.isLoginIDBlank
                            ? nil
                            : .start(self.screenState.loginID, type: self.screenState.verificationLoginIDType)
                    }
                }

            switch screenState.verificationLoginIDType {
            case .email:
                log.add("Email Verification started")
                let operationResult: OperationResult<AccessOrProofToken, EmailVerificationOperationFailure>
                if uiMode == .default {
                    operationResult = await operations.verifications.email.start().whenSettled()
                } else {
                    let controller = operations.verifications.email.useAppHostedComponent.start()
                    emailVerificationOperationUIController = controller
                    operationResult = await controller.whenSettled()

                    if self.emailVerificationOperationUIController === controller {
                        self.emailVerificationOperationUIController = nil
                    }
                }
                operationResult
                    .onSuccess { value in
                        let accessToken: AccessToken?
                        if case .accessToken(let token) = value {
                            accessToken = token
                        } else {
                            accessToken = nil
                        }
                        self.screenState.accessToken = accessToken
                        self.screenState.useAccessToken = self.screenState.useAccessToken && accessToken != nil
                        self.log.add("Verification succeeded: \(value)")
                    }
                    .onCanceled { reason in self.log.add("Verification canceled: \(reason)") }
                    .onError { error in
                        self.log.add("Verification failed: \(error)")
                    }

            case .phoneNumber:
                log.add("Phone Verification started")
                let operationResult: OperationResult<AccessOrProofToken, PhoneVerificationOperationFailure>
                if uiMode == .default {
                    operationResult = await operations.verifications.phone.start().whenSettled()
                } else {
                    let controller = operations.verifications.phone.useAppHostedComponent.start()
                    phoneVerificationOperationUIController = controller
                    operationResult = await controller.whenSettled()

                    if self.phoneVerificationOperationUIController === controller {
                        self.phoneVerificationOperationUIController = nil
                    }
                }
                operationResult
                    .onSuccess { value in
                        let accessToken: AccessToken?
                        if case .accessToken(let token) = value {
                            accessToken = token
                        } else {
                            accessToken = nil
                        }
                        self.screenState.accessToken = accessToken
                        self.screenState.useAccessToken = self.screenState.useAccessToken && accessToken != nil
                        self.log.add("Verification succeeded: \(value)")
                    }
                    .onCanceled { reason in self.log.add("Verification canceled: \(reason)") }
                    .onError { error in
                        self.log.add("Verification failed: \(error)")
                    }

            default:
                preconditionFailure("Unsupported verification login ID type: \(self.screenState.verificationLoginIDType)")
            }
        }
    }

    func startPasskeyCreateEnrollOperation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Passkey Create started")

            screenState.attestationResponse = nil

            await ownID.ops
                .withContext { context in
                    if self.screenState.useAccessToken {
                        context.authz = self.screenState.accessToken.map { .fromToken($0) }
                    } else {
                        context.authz =
                            self.screenState.isLoginIDBlank
                            ? nil
                            : .start(self.screenState.loginID, type: self.screenState.loginIDType)
                    }
                }
                .passkeys.create.start()
                .whenSettled()
                .onSuccess { response in
                    self.screenState.attestationResponse = response
                    self.log.add("Passkey Create succeeded: \(response)")
                }
                .onCanceled { reason in
                    self.log.add("Passkey Create canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Passkey Create failed: \(error)")
                }
        }
    }

    func startPasskeyEnrollOperation() {
        guard let attestationResponse = screenState.attestationResponse, let accessToken = screenState.accessToken else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Passkey Enroll started")

            await ownID.ops
                .withContext { context in
                    context.authz = .fromToken(accessToken)
                }
                .passkeys.enroll
                .start(params: PasskeyEnrollOperationParams(proofToken: attestationResponse.proofToken, accessToken: nil))
                .whenSettled()
                .onSuccess {
                    self.screenState.attestationResponse = nil
                    self.log.add("Passkey Enroll succeeded")
                }
                .onCanceled { reason in
                    self.log.add("Passkey Enroll canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Passkey Enroll failed: \(error)")
                }
        }
    }

    func startPasskeyAssertionOperation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Passkey Assertion started")

            await ownID.ops
                .withContext { context in
                    if self.screenState.useAccessToken {
                        context.authz = self.screenState.accessToken.map { .fromToken($0) }
                    } else {
                        context.authz =
                            self.screenState.isLoginIDBlank
                            ? nil
                            : .start(self.screenState.loginID, type: self.screenState.loginIDType)
                    }
                }
                .passkeys.auth.start()
                .whenSettled()
                .onSuccess { accessToken in
                    self.screenState.accessToken = accessToken
                    self.log.add("Passkey Assertion succeeded: \(accessToken)")
                }
                .onCanceled { reason in
                    self.log.add("Passkey Assertion canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Passkey Assertion failed: \(error)")
                }
        }
    }

    func startDiscoverOperation() {
        guard screenState.canStartDiscoverOperation else { return }
        let loginID = screenState.loginID

        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Discover started")

            await ownID.ops
                .withContext { context in
                    context.authz = .start(loginID, type: self.screenState.loginIDType)
                }
                .login.start()
                .whenSettled()
                .onSuccess { response in
                    if case .success(let success) = response {
                        self.screenState.accessToken = success.accessToken
                    }
                    self.log.add("Discover result: \(response)")
                }
                .onCanceled { reason in
                    self.log.add("Discover canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Discover failed: \(error)")
                }
        }
    }

    func startLoginOperation() {
        guard let accessToken = screenState.accessToken else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Login started")

            await ownID.ops
                .withContext { context in
                    context.authz = .fromToken(accessToken)
                }
                .login.start()
                .whenSettled()
                .onSuccess { response in
                    if case .success(let success) = response {
                        self.screenState.accessToken = success.accessToken
                    }
                    self.log.add("Login result: \(response)")
                }
                .onCanceled { reason in
                    self.log.add("Login canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Login failed: \(error)")
                }
        }
    }

    func startSignInWithAppleOperation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Sign In with Apple started")

            await ownID.ops
                .withContext { context in
                    context.authz = self.screenState.accessToken.map { .fromToken($0) }
                }
                .socialLogin.signInWithApple.start()
                .whenSettled()
                .onSuccess { response in
                    self.screenState.loginID = response.loginID.id
                    self.screenState.loginIDType = response.loginID.type
                    self.screenState.accessToken = response.accessToken
                    self.log.add("Sign In with Apple succeeded: \(response)")
                }
                .onCanceled { reason in
                    self.log.add("Sign In with Apple canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Sign In with Apple failed: \(error)")
                }
        }
    }

    func startSignInWithGoogleOperation() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            log.add("Sign In with Google started")

            await ownID.ops
                .withContext { context in
                    context.authz = self.screenState.accessToken.map { .fromToken($0) }
                }
                .socialLogin.signInWithGoogle.start()
                .whenSettled()
                .onSuccess { response in
                    self.screenState.loginID = response.loginID.id
                    self.screenState.loginIDType = response.loginID.type
                    self.screenState.accessToken = response.accessToken
                    self.log.add("Sign In with Google succeeded: \(response)")
                }
                .onCanceled { reason in
                    self.log.add("Sign In with Google canceled: \(reason)")
                }
                .onError { error in
                    self.log.add("Sign In with Google failed: \(error)")
                }
        }
    }

    func clearOperationControllers() {
        loginIDOperationUIController = nil
        emailVerificationOperationUIController = nil
        phoneVerificationOperationUIController = nil
    }

}
