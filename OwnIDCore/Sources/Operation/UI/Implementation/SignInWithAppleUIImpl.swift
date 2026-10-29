import Foundation
import UIKit

internal final class SignInWithAppleUIImpl: SignInWithAppleUI, @unchecked Sendable {
    private let uiContextProvider: @Sendable () throws -> any UIContextProvider
    private let provider: @Sendable () throws -> any AppleSignInProvider
    private let logger: OwnIDLogRouter?
    private var active: [(id: UUID, provider: any AppleSignInProvider)] = []

    init(
        uiContextProvider: @escaping @Sendable () throws -> any UIContextProvider,
        provider: @escaping @Sendable () throws -> any AppleSignInProvider,
        logger: OwnIDLogRouter?
    ) {
        self.uiContextProvider = uiContextProvider
        self.provider = provider
        self.logger = logger
    }

    @MainActor
    func signIn(clientID: String, nonce: String?) async -> SocialSignInResult {
        do {
            let apple = try provider()
            let window: UIWindow
            do {
                window = try uiContextProvider().current().requireWindow()
            } catch {
                logger?.logW(source: self, prefix: #function, message: "UI context resolution failed", cause: error)
                return .fail(
                    error: .general("Failed to resolve a presentation window: \(error.localizedDescription)", error.asSendableError())
                )
            }
            let requestID = UUID()
            self.active.append((requestID, apple))
            defer {
                if let index = self.active.firstIndex(where: { $0.id == requestID }) {
                    self.active.remove(at: index)
                }
            }
            return await apple.signIn(window: window, params: SocialSignInParams(clientID: clientID, nonce: nonce))
        } catch let missing as MissingDependencyError {
            return .fail(error: .general("Missing dependency: \(missing.dependencyName)", missing))
        } catch {
            return .fail(error: .general(error.localizedDescription, error))
        }
    }

    @MainActor
    func cancel() {
        active.last?.provider.cancel()
    }
}
