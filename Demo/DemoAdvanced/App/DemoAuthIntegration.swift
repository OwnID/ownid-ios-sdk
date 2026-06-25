import Combine
import Foundation
import OwnIDCore

struct CurrentUser: Equatable {
    let email: String
    let name: String?
    let accessToken: AccessToken?
}

@MainActor
protocol DemoAuthIntegration: AnyObject {
    var currentSession: DemoUserSession? { get }
    var isSignedIn: Bool { get }

    func signIn(email: String, password: String) async throws
    func registerAndSignIn(name: String, email: String, password: String, ownIdData: String?) async throws
    func createUser(name: String, email: String, password: String, ownIdData: String?) async throws
    func loadCurrentUser() async throws -> CurrentUser
    func signOut()
}

@MainActor
enum DemoAuthIntegrationProvider {
    private static var storedIntegration: CustomDemoAuthIntegration?

    static var integration: CustomDemoAuthIntegration {
        get {
            guard let storedIntegration else {
                preconditionFailure("DemoAuthIntegrationProvider.integration must be configured before use.")
            }
            return storedIntegration
        }
        set {
            storedIntegration = newValue
        }
    }
}

@MainActor
final class CustomDemoAuthIntegration: ObservableObject, DemoAuthIntegration {
    @Published private(set) var currentSession: DemoUserSession?

    var isSignedIn: Bool {
        currentSession != nil
    }

    private let identityPlatform: DemoIdentityPlatform
    private let sessionStorage: DemoUserSessionStorage

    init(
        identityPlatform: DemoIdentityPlatform,
        sessionStorage: DemoUserSessionStorage
    ) {
        self.identityPlatform = identityPlatform
        self.sessionStorage = sessionStorage
        currentSession = sessionStorage.currentSession
    }

    func signIn(email: String, password: String) async throws {
        save(try await identityPlatform.login(email: email, password: password))
    }

    func registerAndSignIn(name: String, email: String, password: String, ownIdData: String?) async throws {
        save(try await identityPlatform.register(name: name, email: email, password: password, ownIdData: ownIdData))
    }

    func createUser(name: String, email: String, password: String, ownIdData: String?) async throws {
        _ = try await identityPlatform.register(name: name, email: email, password: password, ownIdData: ownIdData)
    }

    func loadCurrentUser() async throws -> CurrentUser {
        guard let session = currentSession else {
            throw DemoIdentityError.invalidResponse
        }

        do {
            let user = try await identityPlatform.getProfileByToken(session: session)
            return CurrentUser(email: user.email, name: user.name, accessToken: session.accessToken)
        } catch {
            signOut()
            throw error
        }
    }

    func signOut() {
        currentSession = nil
        sessionStorage.clear()
    }

    func save(_ session: DemoUserSession) {
        currentSession = session
        sessionStorage.save(session)
    }

    func authenticateSession(email: String, password: String) async throws -> DemoUserSession {
        try await identityPlatform.login(email: email, password: password)
    }
}
