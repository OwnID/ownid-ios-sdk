import Foundation
import UIKit

internal final class SignInWithAppleUIImpl: SignInWithAppleUI, @unchecked Sendable {
    private let provider: @Sendable () throws -> any SignInWithApple
    private var cached: (any SignInWithApple)? = nil

    init(provider: @escaping @Sendable () throws -> any SignInWithApple) {
        self.provider = provider
    }

    @MainActor
    func signIn(clientID: String, nonce: String?, window: UIWindow?) async -> SocialResult {
        do {
            let apple = try provider()
            self.cached = apple
            defer { self.cached = nil }
            return await apple.signIn(params: SignInWithSocialParams(clientID: clientID, nonce: nonce, window: window))
        } catch let missing as MissingDependencyError {
            return .fail(error: .general("Missing dependency: \(missing.dependencyName)", missing))
        } catch {
            return .fail(error: .general(error.localizedDescription, error))
        }
    }

    @MainActor
    func cancel() {
        cached?.cancel()
    }
}
