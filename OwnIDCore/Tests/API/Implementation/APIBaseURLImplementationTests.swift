import Foundation
import Testing

@testable import OwnIDCore

struct APIBaseURLImplementationTests {

    @Test(arguments: [
        (OwnIDEnv.prod, OwnIDRegion.us, "https://App123.server.ownid.com/api"),
        (OwnIDEnv.prod, OwnIDRegion.eu, "https://App123.server.ownid-eu.com/api"),
        (OwnIDEnv.uat, OwnIDRegion.us, "https://App123.server.uat.ownid.com/api"),
        (OwnIDEnv.uat, OwnIDRegion.eu, "https://App123.server.uat.ownid-eu.com/api"),
    ])
    func `Base URL Uses Environment Prefix And Region Suffix`(
        env: OwnIDEnv,
        region: OwnIDRegion,
        expected: String
    ) throws {
        let configuration = try OwnIDConfigurationImpl(appID: "App123", env: env, region: region)

        let baseURL = try APIBaseURLImpl(configuration: configuration).getBaseURL()

        #expect(baseURL.absoluteString == expected)
    }

    @Test func `Base URL uses source-owned internal environment`() throws {
        let configuration = try buildJSONConfiguration(#"{"appID":"App123","env":"DEV","region":"EU"}"#)

        let baseURL = try APIBaseURLImpl(configuration: configuration).getBaseURL()

        #expect(baseURL.absoluteString == "https://App123.server.dev.ownid-eu.com/api")
    }

    @Test func `Root URL replaces derived host and appends API path`() throws {
        let configuration = try OwnIDConfigurationImpl(
            appID: "App123",
            env: .uat,
            region: .eu,
            rootURL: "https://edge.example.com/root?debug=true#fragment"
        )

        let baseURL = try APIBaseURLImpl(configuration: configuration).getBaseURL()

        #expect(baseURL.absoluteString == "https://edge.example.com/root/api")
    }

    private func buildJSONConfiguration(_ json: String) throws -> any OwnIDConfiguration {
        let builder = OwnIDJSONConfigurationBuilder()
        builder.json = json
        return try builder.build().configuration
    }
}
