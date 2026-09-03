import Combine
import OwnIDCore

@MainActor
final class CurrentUserViewModel: ObservableObject {
    var isRunning: Bool { enrollmentTask != nil }

    @Published private(set) var enrollmentResultMessage: String?

    let log = LogStore()

    private var controller: (any PasskeyEnrollController)?
    private var enrollmentTask: Task<Void, Never>? {
        didSet { objectWillChange.send() }
    }

    deinit {
        controller?.abort(reason: .userClose())
        enrollmentTask?.cancel()
    }

    func startPasskeyEnrollFlow(accessToken: AccessToken?) {
        guard let accessToken, enrollmentTask == nil else { return }

        enrollmentResultMessage = nil
        log.add("Starting Passkey Enroll Flow...")

        enrollmentTask = Task { @MainActor [weak self] in
            defer {
                self?.controller = nil
                self?.enrollmentTask = nil
            }
            let passkeyEnroll = OwnID.headless
                .withContext { context in context.authz = .fromToken(accessToken) }
                .passkeys.enroll

            var isPasskeyEnrollAvailable = false
            await passkeyEnroll.availability()
                .onAvailable { isPasskeyEnrollAvailable = true }
                .onUnavailable { [weak self] message in
                    self?.enrollmentResultMessage = "Enrollment failed"
                    self?.log.add("Passkey Enroll Flow is not available: \(message)")
                }

            guard isPasskeyEnrollAvailable, !Task.isCancelled else {
                return
            }

            let controller: any PasskeyEnrollController
            do {
                guard let owner = self else { return }
                controller = passkeyEnroll.start()
                owner.controller = controller
            }

            await controller.whenSettled()
                .onSuccess { [weak self] response in
                    self?.enrollmentResultMessage = "Enrollment successful"
                    self?.log.add("Passkey Enroll Flow succeeded: \(response.loginID)")
                }
                .onCanceled { [weak self] reason in self?.log.add("Passkey Enroll Flow canceled: \(reason)") }
                .onError { [weak self] error in
                    self?.enrollmentResultMessage = "Enrollment failed"
                    self?.log.add("Passkey Enroll Flow failed: \(error)")
                }
        }
    }
}
