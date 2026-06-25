import Combine
import Foundation
import OwnIDCore

struct DemoUserSession: Codable, Equatable {
    let token: String
    var accessToken: AccessToken? = nil
}

struct DemoUser: Codable, Equatable {
    let email: String
    let name: String?
}

private struct DemoRegisterRequest: Encodable {
    let name: String
    let email: String
    let password: String
    let ownIdData: String?
}

private struct DemoLoginRequest: Encodable {
    let email: String
    let password: String
}

enum DemoIdentityError: LocalizedError {
    case invalidResponse
    case transport(String)
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .transport(let message):
            return message
        case .backend(let message):
            return message
        }
    }
}

@MainActor
final class DemoUserSessionStorage: ObservableObject {
    static let shared = DemoUserSessionStorage()

    @Published private(set) var currentSession: DemoUserSession?

    private let userDefaults: UserDefaults
    private let defaultsKey = "saved_session_json"

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        currentSession = userDefaults.data(forKey: defaultsKey)
            .flatMap { data in try? JSONDecoder().decode(DemoUserSession.self, from: data) }
    }

    func save(_ session: DemoUserSession) {
        currentSession = session
        userDefaults.set(try? JSONEncoder().encode(session), forKey: defaultsKey)
    }

    func clear() {
        currentSession = nil
        userDefaults.removeObject(forKey: defaultsKey)
    }
}

final class DemoIdentityPlatform {
    private let baseURL: URL
    private let urlSession: URLSession

    init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func register(name: String, email: String, password: String, ownIdData: String?) async throws -> DemoUserSession {
        try await post("register", body: DemoRegisterRequest(name: name, email: email, password: password, ownIdData: ownIdData))
    }

    func login(email: String, password: String) async throws -> DemoUserSession {
        try await post("login", body: DemoLoginRequest(email: email, password: password))
    }

    func getProfileByToken(session snapshot: DemoUserSession) async throws -> DemoUser {
        try await get("profile", bearerToken: snapshot.token)
    }

    private func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func get<Response: Decodable>(_ path: String, bearerToken: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DemoIdentityError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Request failed with status \(httpResponse.statusCode)"
                throw DemoIdentityError.backend(message)
            }

            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw DemoIdentityError.invalidResponse
            }
        } catch let error as DemoIdentityError {
            throw error
        } catch {
            throw DemoIdentityError.transport(error.localizedDescription)
        }
    }

    @MainActor
    func passwordLogin(email: String, password: String) async throws {
        let session = try await login(email: email, password: password)
        DemoUserSessionStorage.shared.save(session)
    }

    @MainActor
    func registerAndSaveSession(name: String, email: String, password: String, ownIdData: String?) async throws {
        let session = try await register(name: name, email: email, password: password, ownIdData: ownIdData)
        DemoUserSessionStorage.shared.save(session)
    }

    @MainActor
    func loadCurrentUser(session: DemoUserSession) async throws -> DemoUser {
        do {
            return try await getProfileByToken(session: session)
        } catch {
            DemoUserSessionStorage.shared.clear()
            throw error
        }
    }

    @MainActor
    func logout() {
        DemoUserSessionStorage.shared.clear()
    }
}

extension DemoUserSession {
    fileprivate static func from(sessionPayload: String?, accessToken: AccessToken) throws -> DemoUserSession {
        guard let payloadData = sessionPayload?.data(using: .utf8) else {
            throw DemoIdentityError.invalidResponse
        }

        var session = try JSONDecoder().decode(Self.self, from: payloadData)
        session.accessToken = accessToken
        return session
    }
}

extension OwnIDProvidersRegistrar {
    mutating func demoIdentityProviders(identityPlatform: DemoIdentityPlatform) {
        sessionCreate { provider in
            provider.isAvailable { params in params.loginID.type == .email }
            provider.create { params in
                do {
                    let demoSession = try DemoUserSession.from(sessionPayload: params.sessionPayload, accessToken: params.accessToken)
                    DemoUserSessionStorage.shared.save(demoSession)
                    return .success(SessionOutput(session: demoSession))
                } catch {
                    return .failure(error)
                }
            }
        }

        passwordAuthenticate { provider in
            provider.isAvailable { params in params.loginID.type == .email }
            provider.authenticate { params in
                do {
                    let session = try await identityPlatform.login(email: params.loginID.id, password: params.password)
                    DemoUserSessionStorage.shared.save(session)
                    return .success(SessionOutput(session: session))
                } catch {
                    return .failure(error)
                }
            }
        }
    }
}
