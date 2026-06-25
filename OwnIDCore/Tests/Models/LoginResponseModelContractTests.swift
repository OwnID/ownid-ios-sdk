import Foundation
import OwnIDCore
import Testing

struct LoginResponseModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Auth method decodes legacy aliases and unknown as unknown`() throws {
        let decoded = try modelJSON.decoder.decode(
            [AuthMethod].self,
            from: Data(#"["biometrics","desktop-biometrics","email-fallback","sms-fallback","unexpected"]"#.utf8)
        )

        #expect(decoded == [.passkey, .passkey, .otp, .otp, .unknown])
        #expect(try modelJSON.string(encoding: AuthMethod.magicLink) == #""magic-link""#)
    }

    @Test func `User Codable includes raw login ID and auth method values`() throws {
        let user = User(
            loginID: LoginID(id: "person@example.com", type: .email),
            authMethod: .magicLink
        )

        let encoded = try modelJSON.object(encoding: user)
        #expect((encoded["loginID"] as? [String: String]) == ["id": "person@example.com", "type": "Email"])
        #expect(encoded["authMethod"] as? String == "magic-link")

        let decoded = try modelJSON.decoder.decode(User.self, from: try modelJSON.data(encoding: user))
        #expect(decoded.loginID == user.loginID)
        #expect(decoded.authMethod == user.authMethod)
    }

    @Test func `Auth requirements Codable keeps scores operation order and achievability`() throws {
        let requirements = AuthRequirements(
            targetScore: 10,
            operations: [
                OperationRequirement(score: 3, type: .emailVerification, channels: nil),
                OperationRequirement(score: 7, type: .passkeyAuth, channels: []),
            ]
        )

        #expect(requirements.isTargetScoreAchievable())
        #expect(AuthRequirements(targetScore: 11, operations: requirements.operations).isTargetScoreAchievable() == false)
        #expect(AuthRequirements(targetScore: 0, operations: []).isTargetScoreAchievable())
        #expect(AuthRequirements(targetScore: 1, operations: []).isTargetScoreAchievable() == false)
        #expect(
            requirements.description
                == "AuthRequirements(targetScore=10, operations=[EmailVerification(score=3, channels=[nil]), PasskeyAuth(score=7, channels=[])])"
        )

        let encoded = try modelJSON.object(encoding: requirements)
        #expect(encoded["targetScore"] as? Int == 10)

        let operations = try #require(encoded["operations"] as? [[String: Any]])
        #expect(operations.map { $0["score"] as? Int } == [3, 7])
        #expect(operations.map { $0["type"] as? String } == ["EmailVerification", "PasskeyAuth"])
        #expect(operations[0]["channels"] == nil)
        #expect((operations[1]["channels"] as? [Any])?.isEmpty == true)

        let decoded = try modelJSON.decoder.decode(AuthRequirements.self, from: try modelJSON.data(encoding: requirements))
        #expect(decoded == requirements)
    }

    @Test func `Login response Codable uses synthesized case representation and redacted descriptions`() throws {
        let success = LoginResponse.success(
            .init(accessToken: AccessToken(token: "1234567890ABCDEFGHIJ"), sessionPayload: #"{"session":"secret"}"#)
        )
        let authRequired = LoginResponse.authRequired(
            .init(
                authRequirements: AuthRequirements(
                    targetScore: 1,
                    operations: [OperationRequirement(score: 1, type: .emailVerification, channels: nil)]
                ),
                reason: "more-auth"
            )
        )
        let accountNotFound = LoginResponse.accountNotFound(.init(reason: "missing"))
        let accountBlocked = LoginResponse.accountBlocked(.init(reason: "blocked"))

        #expect(
            success.description
                == "Success(accessToken=AccessToken(token: 12345678..[4]...CDEFGHIJ), sessionPayload='*')"
        )
        #expect(
            authRequired.description
                == "AuthRequired(AuthRequirements(targetScore=1, operations=[EmailVerification(score=1, channels=[nil])]), reason=more-auth)"
        )
        #expect(accountNotFound.description == "AccountNotFound(reason=missing)")
        #expect(accountBlocked.description == "AccountBlocked(reason=blocked)")

        #expect((try modelJSON.object(encoding: success))["success"] != nil)
        #expect((try modelJSON.object(encoding: authRequired))["authRequired"] != nil)
        #expect((try modelJSON.object(encoding: accountNotFound))["accountNotFound"] != nil)
        #expect((try modelJSON.object(encoding: accountBlocked))["accountBlocked"] != nil)

        #expect(
            try modelJSON.decoder.decode(LoginResponse.self, from: try modelJSON.data(encoding: success)).description == success.description
        )
        #expect(
            try modelJSON.decoder.decode(LoginResponse.self, from: try modelJSON.data(encoding: authRequired)).description
                == authRequired.description
        )
        #expect(
            try modelJSON.decoder.decode(LoginResponse.self, from: try modelJSON.data(encoding: accountNotFound)).description
                == accountNotFound.description
        )
        #expect(
            try modelJSON.decoder.decode(LoginResponse.self, from: try modelJSON.data(encoding: accountBlocked)).description
                == accountBlocked.description
        )
    }
}
