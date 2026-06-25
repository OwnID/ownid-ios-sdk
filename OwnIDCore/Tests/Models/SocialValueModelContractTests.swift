import Foundation
import OwnIDCore
import Testing

struct SocialValueModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Social provider ID decodes case insensitively and encodes canonical value`() throws {
        #expect(try modelJSON.decoder.decode(SocialProviderID.self, from: Data(#""apple""#.utf8)) == .apple)
        #expect(try modelJSON.decoder.decode(SocialProviderID.self, from: Data(#""GOOGLE""#.utf8)) == .google)
        #expect(SocialProviderID(rawValue: "apple") == nil)
        #expect(try modelJSON.string(encoding: SocialProviderID.apple) == #""Apple""#)

        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(SocialProviderID.self, from: Data(#""microsoft""#.utf8))
        }
    }

    @Test func `Social challenge Codable uses public keys and keeps raw values`() throws {
        let challenge = SocialChallenge(
            challengeID: ChallengeID("social-challenge"),
            timeout: Timeout(milliseconds: -10),
            clientID: "client-id",
            challengeURL: "https://login.example.test/challenge"
        )

        #expect(challenge.timeout == Timeout(milliseconds: 0))
        #expect(
            challenge.description
                == "SocialChallenge(challengeId: social-challenge, timeout: 0, clientId: client-id, challengeUrl: Optional(\"https://login.example.test/challenge\"))"
        )

        let encoded = try modelJSON.object(encoding: challenge)
        #expect(encoded["challengeId"] as? String == "social-challenge")
        #expect(encoded["challengeID"] == nil)
        #expect(encoded["timeout"] as? Int == 0)
        #expect(encoded["clientId"] as? String == "client-id")
        #expect(encoded["clientID"] == nil)
        #expect(encoded["challengeUrl"] as? String == "https://login.example.test/challenge")
        #expect(encoded["challengeURL"] == nil)

        let decoded = try modelJSON.decoder.decode(SocialChallenge.self, from: try modelJSON.data(encoding: challenge))
        #expect(decoded == challenge)

        let noURL = SocialChallenge(
            challengeID: ChallengeID("no-url"),
            timeout: Timeout(milliseconds: 1),
            clientID: "client-id",
            challengeURL: nil
        )
        #expect(try modelJSON.object(encoding: noURL)["challengeUrl"] == nil)
    }

    @Test func `Access token with user info Codable uses public keys and redacts sensitive fields`() throws {
        let token = AccessTokenWithUserInfo(
            accessToken: AccessToken(token: "1234567890ABCDEFGHIJ"),
            loginID: LoginID(id: "person@example.com", type: .email),
            userInfo: ["email": "person@example.com", "name": "Example"],
            provider: .google
        )

        let encoded = try modelJSON.object(encoding: token)
        #expect((encoded["accessToken"] as? [String: String])?["token"] == "1234567890ABCDEFGHIJ")
        #expect((encoded["loginId"] as? [String: String])?["id"] == "person@example.com")
        #expect(encoded["loginID"] == nil)
        #expect((encoded["userInfo"] as? [String: String]) == ["email": "person@example.com", "name": "Example"])
        #expect(encoded["provider"] as? String == "Google")

        let decoded = try modelJSON.decoder.decode(AccessTokenWithUserInfo.self, from: try modelJSON.data(encoding: token))
        #expect(decoded == token)
        #expect(
            token.description
                == "AccessTokenWithUserInfo(accessToken: AccessToken(token: 12345678..[4]...CDEFGHIJ), loginID: LoginID(id: 'p****n@example.com', type: email), userInfo: '*', provider: Google)"
        )
    }

    @Test func `OAuth response type Codable uses synthesized case representation`() throws {
        #expect(try modelJSON.object(encoding: OAuthResponseType.code)["code"] != nil)
        #expect(try modelJSON.object(encoding: OAuthResponseType.idToken)["idToken"] != nil)
        #expect(try modelJSON.decoder.decode(OAuthResponseType.self, from: Data(#"{"code":{}}"#.utf8)) == .code)
        #expect(try modelJSON.decoder.decode(OAuthResponseType.self, from: Data(#"{"idToken":{}}"#.utf8)) == .idToken)
    }
}
