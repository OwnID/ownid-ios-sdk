import Foundation
import OwnIDCore
import Testing

struct OperationModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Operation types expose Own ID wire values`() {
        #expect(OperationType.emailVerification.rawValue == "EmailVerification")
        #expect(OperationType.passkeyAuth.rawValue == "PasskeyAuth")
    }

    @Test func `Operation descriptions use wire values and redact channel value`() {
        let channel = OperationChannel(channel: "person@example.com", id: "email-main")
        let requirement = OperationRequirement(score: 10, type: .emailVerification, channels: [channel])
        let operationID = OperationID(type: .passkeyAuth, id: "opaque-id")

        #expect(channel.channel == "person@example.com")
        #expect(channel.id == "email-main")
        #expect(channel.description == "OperationChannel(channel: '*', id: 'email-main')")
        #expect(requirement.description == "EmailVerification(score=10, channels=[OperationChannel(channel: '*', id: 'email-main')])")
        #expect(operationID.description == "PasskeyAuth:opaque-id")
    }

    @Test func `Operation requirement Codable uses public keys and strict operation type values`() throws {
        let requirement = OperationRequirement(
            score: -5,
            type: .emailVerification,
            channels: [OperationChannel(channel: "person@example.com", id: "email-main")]
        )

        let encoded = try modelJSON.object(encoding: requirement)
        #expect(encoded["score"] as? Int == -5)
        #expect(encoded["type"] as? String == "EmailVerification")

        let channels = try #require(encoded["channels"] as? [[String: String]])
        #expect(channels == [["channel": "person@example.com", "id": "email-main"]])

        let decoded = try modelJSON.decoder.decode(OperationRequirement.self, from: try modelJSON.data(encoding: requirement))
        #expect(decoded == requirement)

        let nilChannels = OperationRequirement(score: 1, type: .passkeyAuth, channels: nil)
        #expect(try modelJSON.object(encoding: nilChannels)["channels"] == nil)
        #expect(throws: (any Error).self) {
            try modelJSON.decoder.decode(OperationRequirement.self, from: Data(#"{"score":1,"type":"PasskeyAuthentication"}"#.utf8))
        }
    }
}
