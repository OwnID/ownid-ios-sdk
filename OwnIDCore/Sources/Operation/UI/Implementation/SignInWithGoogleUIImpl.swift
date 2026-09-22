import Foundation
import UIKit

internal final class SignInWithGoogleUIImpl: SignInWithGoogleUI, @unchecked Sendable {
    private let uiContextProvider: @Sendable () throws -> any UIContextProvider
    private let provider: @Sendable () throws -> any SignInWithGoogle
    private let logger: OwnIDLogRouter?
    private var active: [(id: UUID, provider: any SignInWithGoogle)] = []

    init(
        uiContextProvider: @escaping @Sendable () throws -> any UIContextProvider,
        provider: @escaping @Sendable () throws -> any SignInWithGoogle,
        logger: OwnIDLogRouter?
    ) {
        self.uiContextProvider = uiContextProvider
        self.provider = provider
        self.logger = logger
    }

    @MainActor
    func signIn(clientID: String, nonce: String?) async -> SocialResult {
        do {
            let google = try provider()
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
            self.active.append((requestID, google))
            defer {
                if let index = self.active.firstIndex(where: { $0.id == requestID }) {
                    self.active.remove(at: index)
                }
            }
            return await google.signIn(window: window, params: SignInWithSocialParams(clientID: clientID, nonce: nonce))
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
