import Combine
import Foundation
import OwnIDCore

@MainActor
final class EliteFlowViewModel: ObservableObject {
    struct PendingRegistration: Identifiable {
        let id = UUID()
        let email: String
        let ownIdData: String?
    }

    @Published private(set) var isRunning = false
    @Published private(set) var pendingRegistration: PendingRegistration?
    let log = LogStore()

    private var eliteFlowController: (any EliteFlowController)?

    deinit {
        eliteFlowController?.abort(reason: .userClose(details: "Elite Flow owner deinitialized"))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        log.add("Starting Elite Flow...")

        Task { @MainActor [weak self] in
            let flowContext = EliteFlowContext { builder in
                builder.options { options in
                    options.webViewIsInspectable = true
                }

                builder.events { events in
                    events.onNativeAction { [weak self] loginID, ownIdData, accessToken in
                        self?.log.add(
                            "Elite Flow: onNativeAction: \(loginID), ownIdData=\(ownIdData ?? "null"), accessToken=\(Self.describe(accessToken))"
                        )
                        self?.pendingRegistration = PendingRegistration(email: loginID, ownIdData: ownIdData)
                    }

                    events.onFinish { [weak self] loginID, authMethod, accessToken in
                        self?.log.add(
                            "Elite Flow: onFinish: \(loginID), authMethod=\(authMethod), accessToken=\(Self.describe(accessToken))"
                        )
                    }

                    events.onError { [weak self] error in
                        self?.log.add("Elite Flow: onError: \(String(describing: error))")
                    }

                    events.onClose { [weak self] in
                        self?.log.add("Elite Flow: onClose")
                    }
                }
            }

            let controller = OwnID.flows.elite.start(flowContext)
            self?.eliteFlowController = controller

            await controller.whenSettled()
                .onSuccess { self?.log.add("Elite Flow succeeded") }
                .onCanceled { reason in self?.log.add("Elite Flow Canceled: \(reason)") }
                .onError { error in self?.log.add("Elite Flow Failed: \(error)") }
            self?.eliteFlowController = nil
            self?.isRunning = false
        }
    }

    func cancelRegistration() {
        pendingRegistration = nil
        log.add("Elite Flow: registration canceled")
    }

    func completeRegistration(name: String) async {
        guard let registration = pendingRegistration else { return }
        pendingRegistration = nil

        do {
            let session = try await DemoBaseApp.identityPlatform.register(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: registration.email,
                password: "SomeRandomLongAndCrypticPassword",
                ownIdData: registration.ownIdData
            )
            DemoUserSessionStorage.shared.save(session)
            log.add("Elite Flow: Registration succeeded")
        } catch {
            log.add("Elite Flow: Registration failed: \(error)")
        }
    }

    private static func describe<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "nil"
    }
}
