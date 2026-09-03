import Combine
import Foundation
import OwnIDCore

@MainActor
final class HeadlessViewModel: ObservableObject {
    struct ScreenState {
        var email = ""
        var flowState: FlowState = .idle
    }

    enum FlowState {
        case idle
        case loading
        case emailVerification(
            challenge: VerificationChallenge,
            resendCount: Int,
            resendAvailableAt: TimeInterval,
            error: UIError?,
            busy: Bool
        )
        case completed
        case failed

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var isActive: Bool {
            switch self {
            case .loading, .emailVerification:
                return true
            case .idle, .completed, .failed:
                return false
            }
        }
    }

    @Published private(set) var screenState = ScreenState()

    let log = LogStore()

    private lazy var emailVerification = EmailVerificationCoordinator(viewModel: self)

    func onEmailChanged(_ value: String) {
        screenState.email = value
    }

    func start() {
        Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        let email = screenState.email
        screenState.flowState = .loading

        let headless = OwnID.headless.withContext { context in
            context.authz = .start(email, type: .email)
        }

        let response = await headless.auth.discover.start()
            .onError { error in
                log.add("Discover failed: \(error.toUIError())\n\(error)")
                screenState.flowState = .failed
            }
            .onCanceled {
                log.add("Discover canceled")
                screenState.flowState = .failed
            }

        guard let response = response.getOrNil() else { return }

        switch response {
        case .success(let success):
            log.add("Discover succeeded with session: \(success)")
            screenState.flowState = .completed
            passkeyEnroll(success.accessToken)

        case .authRequired(let authRequired):
            await handleAuthRequirements(authRequired.authRequirements, headless: headless)

        case .accountNotFound(let accountNotFound):
            log.add("Discover: account not found: \(accountNotFound.reason ?? "Account not found")")

            if await createUser(email: email) {
                screenState.flowState = .idle
                await run()
                return
            }

            screenState.flowState = .failed

        case .accountBlocked(let accountBlocked):
            log.add("Discover: account blocked: \(accountBlocked.reason ?? "Account is blocked")")
            screenState.flowState = .failed
        }
    }

    private func handleAuthRequirements(_ authRequirements: AuthRequirements, headless: OwnIDHeadless) async {
        let hasPasskeyAuth = authRequirements.operations.contains { operation in operation.type == .passkeyAuth }
        var shouldEnrollAfterOTP = !hasPasskeyAuth

        if hasPasskeyAuth {
            var passkeyMissing = false
            let accessToken = await runPasskeyAuthentication(headless: headless) {
                passkeyMissing = true
            }

            if let accessToken {
                let accessToken = await login(accessToken: accessToken)
                if accessToken != nil {
                    screenState.flowState = .completed
                    return
                }
            }
            shouldEnrollAfterOTP = passkeyMissing
        }

        if authRequirements.operations.contains(where: { operation in operation.type == .emailVerification }) {
            switch await emailVerification.run(headless: headless) {
            case .accessToken(let verifiedAccessToken):
                if let accessToken = await login(accessToken: verifiedAccessToken, registerMissingUser: true) {
                    screenState.flowState = .completed
                    if shouldEnrollAfterOTP {
                        passkeyEnroll(accessToken)
                    }
                } else {
                    screenState.flowState = .failed
                }

            case .proofToken(let proofToken):
                log.add("Email Verification returned proof token: \(proofToken)")
                screenState.flowState = .failed

            case nil:
                break
            }
            return
        }

        log.add("No verification method available")
        screenState.flowState = .failed
    }

    private func runPasskeyAuthentication(headless: OwnIDHeadless, onMissingPasskey: () -> Void = {}) async -> AccessToken? {
        let passkeyAuth = headless.passkeys.auth

        var isPasskeyAuthAvailable = false
        await passkeyAuth.availability()
            .onAvailable { isPasskeyAuthAvailable = true }
            .onUnavailable { message in log.add("Passkey Authentication is not available: \(message)") }

        guard isPasskeyAuthAvailable else {
            return nil
        }

        return await passkeyAuth.start().whenSettled()
            .onSuccess { token in log.add("Passkey Authentication succeeded: \(token)") }
            .onCanceled { reason in log.add("Passkey Authentication canceled: \(reason)") }
            .onError { error in
                log.add("Passkey Authentication failed: \(error.toUIError())\n\(error)")
                if case .credential(.noApplicablePasskeys) = error {
                    onMissingPasskey()
                }
            }
            .getOrNil()
    }

    private func login(accessToken: AccessToken, registerMissingUser: Bool = false) async -> AccessToken? {
        let headless = OwnID.headless.withContext { context in
            context.authz = .fromToken(accessToken)
        }

        let response = await headless.auth.login.start()
            .onError { error in
                log.add("Login failed: \(error.toUIError())\n\(error)")
            }
            .onCanceled { log.add("Login canceled") }
            .getOrNil()

        guard let response else { return nil }

        switch response {
        case .success(let success):
            log.add("Login succeeded: \(success)")
            return success.accessToken
        case .authRequired(let required):
            log.add("Login: TargetScore not achieved: \(required.reason ?? "null")")
            return nil
        case .accountNotFound(let notFound):
            log.add("Login: Account not found: \(notFound.reason ?? "null")")
            if registerMissingUser, await createUser(email: screenState.email) {
                return await login(accessToken: accessToken)
            }
            return nil
        case .accountBlocked(let blocked):
            log.add("Login: Account blocked: \(blocked.reason ?? "null")")
            return nil
        }
    }

    private func passkeyEnroll(_ accessToken: AccessToken) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let passkeyEnroll = OwnID.headless
                .withContext { context in context.authz = .fromToken(accessToken) }
                .passkeys.enroll

            var isPasskeyEnrollAvailable = false
            await passkeyEnroll.availability()
                .onAvailable { isPasskeyEnrollAvailable = true }
                .onUnavailable { message in self.log.add("Passkey Enroll is not available: \(message)") }

            guard isPasskeyEnrollAvailable else {
                return
            }

            await passkeyEnroll.start().whenSettled()
                .onSuccess { response in self.log.add("Passkey Enroll succeeded: \(response.loginID)") }
                .onCanceled { reason in self.log.add("Passkey Enroll canceled: \(reason)") }
                .onError { error in
                    self.log.add("Passkey Enroll failed: \(error.toUIError())\n\(error)")
                }
        }
    }

    func resendEmailVerification() {
        emailVerification.resend()
    }

    func cancelEmailVerification() {
        emailVerification.cancel()
    }

    func completeEmailVerification(_ otpCode: String) {
        emailVerification.complete(otpCode)
    }

    @MainActor
    private final class EmailVerificationCoordinator {
        private unowned let viewModel: HeadlessViewModel
        private var continuation: CheckedContinuation<AccessOrProofToken?, Never>?
        private var controller: (any EmailVerificationAPIController)?

        init(viewModel: HeadlessViewModel) {
            self.viewModel = viewModel
        }

        func run(headless: OwnIDHeadless) async -> AccessOrProofToken? {
            clear()

            return await withCheckedContinuation { (continuation: CheckedContinuation<AccessOrProofToken?, Never>) in
                self.continuation = continuation

                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: nil)
                        return
                    }

                    await headless.verifications.email.start()
                        .onSuccess { controller in
                            guard self.continuation != nil else { return }

                            self.controller = controller
                            self.viewModel.log.add("Email Verification started: waiting for OTP")
                            self.viewModel.screenState.flowState = .emailVerification(
                                challenge: controller.challenge,
                                resendCount: 0,
                                resendAvailableAt: controller.challenge.resendPolicy.allow
                                    ? ProcessInfo.processInfo.systemUptime + TimeInterval(controller.challenge.resendPolicy.debounce)
                                    : 0,
                                error: nil,
                                busy: false
                            )
                        }
                        .onError { error in
                            guard self.continuation != nil else { return }

                            self.viewModel.log.add("Email Verification failed: \(error.toUIError())\n\(error)")
                            self.viewModel.screenState.flowState = .failed
                            self.finish(nil)
                        }
                        .onCanceled {
                            guard self.continuation != nil else { return }

                            self.viewModel.log.add("Email Verification start canceled")
                            self.viewModel.screenState.flowState = .failed
                            self.finish(nil)
                        }
                }
            }
        }

        func resend() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let viewModel = self.viewModel
                guard
                    case .emailVerification(let challenge, let resendCount, let resendAvailableAt, _, false) = viewModel.screenState
                        .flowState,
                    let controller
                else { return }

                let policy = controller.challenge.resendPolicy
                guard policy.allow, resendCount < policy.attempts, resendAvailableAt <= ProcessInfo.processInfo.systemUptime else { return }

                viewModel.screenState.flowState = .emailVerification(
                    challenge: challenge,
                    resendCount: resendCount,
                    resendAvailableAt: resendAvailableAt,
                    error: nil,
                    busy: true
                )

                await controller.resend()
                    .onSuccess {
                        viewModel.log.add("Email Verification resent")
                        viewModel.screenState.flowState = .emailVerification(
                            challenge: challenge,
                            resendCount: resendCount + 1,
                            resendAvailableAt: ProcessInfo.processInfo.systemUptime + TimeInterval(policy.debounce),
                            error: nil,
                            busy: false
                        )
                    }
                    .onError { error in
                        viewModel.log.add("Email Verification resend: \(error.toUIError())\n\(error)")
                        viewModel.screenState.flowState = .emailVerification(
                            challenge: challenge,
                            resendCount: resendCount,
                            resendAvailableAt: resendAvailableAt,
                            error: error.toUIError(),
                            busy: false
                        )
                    }
                    .onCanceled {
                        viewModel.screenState.flowState = .emailVerification(
                            challenge: challenge,
                            resendCount: resendCount,
                            resendAvailableAt: resendAvailableAt,
                            error: nil,
                            busy: false
                        )
                    }
            }
        }

        func cancel() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let viewModel = self.viewModel
                guard
                    case .emailVerification(let challenge, let resendCount, let resendAvailableAt, _, false) = viewModel.screenState
                        .flowState,
                    let controller
                else { return }

                viewModel.screenState.flowState = .emailVerification(
                    challenge: challenge,
                    resendCount: resendCount,
                    resendAvailableAt: resendAvailableAt,
                    error: nil,
                    busy: true
                )

                await controller.cancel(reason: .userClose())
                    .onSuccess { viewModel.log.add("Email Verification canceled") }
                    .onError { error in
                        viewModel.log.add("Email Verification cancellation: \(error.toUIError())\n\(error)")
                    }

                viewModel.screenState.flowState = .failed
                self.finish(nil)
            }
        }

        func complete(_ otpCode: String) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let viewModel = self.viewModel
                guard
                    case .emailVerification(let challenge, let resendCount, let resendAvailableAt, _, false) = viewModel.screenState
                        .flowState,
                    let controller
                else { return }

                viewModel.screenState.flowState = .emailVerification(
                    challenge: challenge,
                    resendCount: resendCount,
                    resendAvailableAt: resendAvailableAt,
                    error: nil,
                    busy: true
                )

                await controller.completeWithCode(code: otpCode)
                    .onSuccess { token in
                        viewModel.log.add("Email Verification succeeded: \(token)")
                        self.finish(token)
                    }
                    .onError { error in
                        viewModel.log.add("Email Verification: \(error.toUIError())\n\(error)")

                        if case .badRequest(.wrongCode) = error {
                            viewModel.screenState.flowState = .emailVerification(
                                challenge: challenge,
                                resendCount: resendCount,
                                resendAvailableAt: resendAvailableAt,
                                error: error.toUIError(),
                                busy: false
                            )
                        } else {
                            viewModel.screenState.flowState = .failed
                            self.finish(nil)
                        }
                    }
                    .onCanceled {
                        viewModel.screenState.flowState = .emailVerification(
                            challenge: challenge,
                            resendCount: resendCount,
                            resendAvailableAt: resendAvailableAt,
                            error: nil,
                            busy: false
                        )
                    }
            }
        }

        func clear() {
            finish(nil)
        }

        private func finish(_ token: AccessOrProofToken?) {
            guard let continuation else { return }
            self.continuation = nil
            controller = nil
            continuation.resume(returning: token)
        }
    }

    private func createUser(email: String) async -> Bool {
        do {
            try await DemoAuthIntegrationProvider.integration.createUser(
                name: email,
                email: email,
                password: "SomeRandomLongAndCrypticPassword",
                ownIdData: nil
            )
            log.add("Creating demo user: OK")
            return true
        } catch {
            log.add("Creating demo user failed: \(error)")
            return false
        }
    }
}
