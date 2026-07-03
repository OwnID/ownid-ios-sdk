import Foundation
import UIKit

internal final class SignInWithGoogleUIImpl: SignInWithGoogleUI, @unchecked Sendable {
    private let provider: @Sendable () throws -> any SignInWithGoogle
    private var cached: (any SignInWithGoogle)? = nil

    init(provider: @escaping @Sendable () throws -> any SignInWithGoogle) {
        self.provider = provider
    }

    @MainActor
    func signIn(clientID: String, nonce: String?, window: UIWindow?) async -> SocialResult {
        do {
            let google = try provider()
            self.cached = google
            defer { self.cached = nil }
            return await google.signIn(params: SignInWithSocialParams(clientID: clientID, nonce: nonce, window: window))
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
