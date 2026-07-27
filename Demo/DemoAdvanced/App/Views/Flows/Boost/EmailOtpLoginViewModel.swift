import Combine
import Foundation
import OwnIDCore

@MainActor
final class EmailOtpLoginViewModel: ObservableObject {
    @Published private(set) var isRunning = false

    private var flowController: (any BoostLoginFlowController)?

    deinit {
        flowController?.abort(reason: .userClose(details: "Email OTP login owner deinitialized"))
    }

    func startLoginFlow(
        email: String,
        onLogin: @escaping (BoostFlowLoginResponse) -> Void,
        onError: @escaping (BoostLoginFlowFailure) -> Void,
        onCancel: @escaping (Reason) -> Void
    ) {
        guard !isRunning else { return }
        isRunning = true

        let flowContext = BoostFlowContext {
            $0.loginID(email.trimmingCharacters(in: .whitespacesAndNewlines), type: .email)
            $0.allowedAuthOperations = [.emailVerification]
        }

        let controller = OwnID.flows.boost.login.start(flowContext)
        flowController = controller

        Task { @MainActor [weak self] in
            let result = await controller.whenSettled()
            guard let self else { return }

            flowController = nil

            result
                .onSuccess(onLogin)
                .onCanceled(onCancel)
                .onError(onError)
            isRunning = false
        }
    }
}
