import Foundation
import OwnIDCore
import Testing

struct VerificationModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Verification challenge Codable uses public keys and keeps decoded values`() throws {
        let json = """
            {
              "challengeId": "verification-challenge",
              "resendPolicy": {
                "allow": true,
                "attempts": -1,
                "debounce": 0
              },
              "timeout": -50,
              "attempts": -2,
              "methods": {
                "otp": { "length": 2 },
                "magicLink": {}
              },
              "channel": {
                "channel": "person@example.com",
                "id": "email-main"
              }
            }
            """

        let challenge = try modelJSON.decoder.decode(VerificationChallenge.self, from: Data(json.utf8))

        #expect(challenge.challengeID == ChallengeID("verification-challenge"))
        #expect(challenge.resendPolicy.allow == true)
        #expect(challenge.resendPolicy.attempts == -1)
        #expect(challenge.resendPolicy.debounce == 0)
        #expect(challenge.timeout == Timeout(milliseconds: 0))
        #expect(challenge.attempts == -2)
        #expect(challenge.methods.otp?.length == 2)
        #expect(challenge.methods.magicLink != nil)
        #expect(challenge.channel == OperationChannel(channel: "person@example.com", id: "email-main"))

        let encoded = try modelJSON.object(encoding: challenge)
        #expect(encoded["challengeId"] as? String == "verification-challenge")
        #expect(encoded["challengeID"] == nil)
        #expect(encoded["timeout"] as? Int == 0)
        #expect(encoded["attempts"] as? Int == -2)

        let resendPolicy = try #require(encoded["resendPolicy"] as? [String: Any])
        #expect(resendPolicy["allow"] as? Bool == true)
        #expect(resendPolicy["attempts"] as? Int == -1)
        #expect(resendPolicy["debounce"] as? Int == 0)

        let methods = try #require(encoded["methods"] as? [String: Any])
        #expect((methods["otp"] as? [String: Any])?["length"] as? Int == 2)
        #expect(methods["magicLink"] != nil)

        let channel = try #require(encoded["channel"] as? [String: String])
        #expect(channel == ["channel": "person@example.com", "id": "email-main"])
        #expect(
            challenge.description
                == "VerificationChallenge(challengeId: verification-challenge, timeout: 0, attempts: -2, methods: Methods(otp: Optional(OwnIDCore.VerificationChallenge.Methods.Otp(length: 2)), magicLink: Optional(OwnIDCore.VerificationChallenge.Methods.MagicLink())), channel: OperationChannel(channel: '*', id: 'email-main'))"
        )
    }

    @Test func `Verification method wire values are stable and strict`() throws {
        #expect(VerificationMethod.magicLink.rawValue == "MagicLink")
        #expect(VerificationMethod.otp.rawValue == "Otp")
        #expect(try modelJSON.string(encoding: VerificationMethod.magicLink) == #""MagicLink""#)
        #expect(try modelJSON.decoder.decode(VerificationMethod.self, from: Data(#""Otp""#.utf8)) == .otp)
        #expect(VerificationMethod(rawValue: "otp") == nil)
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(VerificationMethod.self, from: Data(#""otp""#.utf8))
        }
    }
}
