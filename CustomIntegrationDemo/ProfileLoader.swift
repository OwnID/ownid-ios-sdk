import Foundation
import AccountView
import OwnIDCoreSDK

struct ProfileLoader {
    private let session = URLSession.shared

    func loadProfile(previousResult: OperationResult) async throws -> AccountModel {
        var request = URLRequest(url: URL(string: "https://node-mongo.custom.demo.dev.ownid.com/api/auth/profile")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(previousResult)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(AccountModel.self, from: data)
    }
}
