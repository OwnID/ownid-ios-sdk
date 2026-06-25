import Foundation
import OwnIDCore
import Testing

struct CoreValueModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Challenge ID Codable keeps raw string value`() throws {
        let challengeID = ChallengeID("  challenge-123  ")

        #expect(challengeID.value == "  challenge-123  ")
        #expect(challengeID.description == "  challenge-123  ")
        #expect(try modelJSON.string(encoding: challengeID) == #""  challenge-123  ""#)

        let decoded = try modelJSON.decoder.decode(ChallengeID.self, from: Data(#""  challenge-123  ""#.utf8))

        #expect(decoded == challengeID)
    }

    @Test func `Timeout clamps negative values and encodes normalized milliseconds`() throws {
        let initialized = Timeout(milliseconds: -25)
        let decoded = try modelJSON.decoder.decode(Timeout.self, from: Data("-25".utf8))

        #expect(initialized.milliseconds == 0)
        #expect(decoded.milliseconds == 0)
        #expect(try modelJSON.string(encoding: initialized) == "0")
        #expect(Timeout(milliseconds: 1) < Timeout(milliseconds: 2))
    }

    @Test(arguments: JSONValuePrimitiveDecodeCase.allCases)
    func `JSON value decodes primitive value to matching case`(_ testCase: JSONValuePrimitiveDecodeCase) throws {
        #expect(try modelJSON.decoder.decode(JSONValue.self, from: Data(testCase.json.utf8)) == testCase.value)
    }

    @Test func `JSON value encodes and accesses nested arrays and dictionaries`() throws {
        let value: JSONValue = [
            "string": "value",
            "int": 2,
            "double": 2.5,
            "bool": false,
            "array": ["first", 3, true],
            "object": ["nested": "field"],
        ]

        #expect(value["string"]?.stringValue == "value")
        #expect(value["int"]?.intValue == 2)
        #expect(value["double"]?.doubleValue == 2.5)
        #expect(value["bool"]?.boolValue == false)
        #expect(value["array"]?[0]?.stringValue == "first")
        #expect(value["array"]?[1]?.intValue == 3)
        #expect(value["array"]?[2]?.boolValue == true)
        #expect(value["array"]?[3] == nil)
        #expect(value["object"]?["nested"]?.stringValue == "field")
        #expect(value["missing"] == nil)
        #expect(JSONValue.string("not-array")[0] == nil)

        let decoded = try modelJSON.decoder.decode(JSONValue.self, from: try modelJSON.data(encoding: value))
        #expect(decoded == value)
    }

    @Test func `JSON value dictionary literal uses last value for duplicate keys`() {
        let value: JSONValue = ["key": "first", "key": "second"]

        #expect(value["key"] == .string("second"))
    }

    @Test func `Language tag Codable uses normalized tag string`() throws {
        let decoded = try modelJSON.decoder.decode(LanguageTag.self, from: Data(#""EN-us""#.utf8))

        #expect(decoded.language == "en")
        #expect(decoded.country == "US")
        #expect(decoded.tagString == "en-US")
        #expect(decoded.description == "en-US")
        #expect(decoded.toLanguageOnly().tagString == "en")
        #expect(try modelJSON.string(encoding: decoded) == #""en-US""#)
    }

    @Test func `Language tag unknown language falls back to default`() throws {
        let decoded = try modelJSON.decoder.decode(LanguageTag.self, from: Data(#""und""#.utf8))

        #expect(decoded == .default)
        #expect(decoded.language == "en")
        #expect(decoded.country == "")
        #expect(decoded.description == "en")
    }

    @Test func `Instance name keeps raw value in equality hashing and description`() {
        let name = InstanceName(value: "  tenant-A  ")

        #expect(InstanceName.default.value == "DEFAULT")
        #expect(name.value == "  tenant-A  ")
        #expect(name.description == "  tenant-A  ")
        #expect(name == InstanceName(value: "  tenant-A  "))
        #expect(name != InstanceName(value: "tenant-A"))
        #expect(Set([name, InstanceName(value: "  tenant-A  ")]).count == 1)
    }

    @Test(arguments: ReasonDescriptionExpectation.allCases)
    func `Reason description keeps stable category and optional details`(_ expectation: ReasonDescriptionExpectation) {
        #expect(expectation.reason.description == expectation.description)
    }

}

struct JSONValuePrimitiveDecodeCase: CustomTestStringConvertible, Sendable {
    let json: String
    let value: JSONValue
    let testDescription: String

    static let allCases = [
        JSONValuePrimitiveDecodeCase(json: #""text""#, value: .string("text"), testDescription: "string"),
        JSONValuePrimitiveDecodeCase(json: "7", value: .int(7), testDescription: "integer"),
        JSONValuePrimitiveDecodeCase(json: "7.5", value: .double(7.5), testDescription: "double"),
        JSONValuePrimitiveDecodeCase(json: "true", value: .bool(true), testDescription: "boolean"),
        JSONValuePrimitiveDecodeCase(json: "null", value: .null, testDescription: "null"),
    ]
}

struct ReasonDescriptionExpectation: CustomTestStringConvertible, Sendable {
    let reason: Reason
    let description: String
    let testDescription: String

    static let allCases = [
        ReasonDescriptionExpectation(reason: .timeout, description: "timeout", testDescription: "timeout"),
        ReasonDescriptionExpectation(reason: .userClose(), description: "userClose", testDescription: "userClose"),
        ReasonDescriptionExpectation(reason: .userClose(details: ""), description: "userClose", testDescription: "empty userClose"),
        ReasonDescriptionExpectation(
            reason: .userClose(details: "sheet dismissed"),
            description: "userClose: sheet dismissed",
            testDescription: "detailed userClose"
        ),
        ReasonDescriptionExpectation(
            reason: .moveToOtherChallenge,
            description: "moveToOtherChallenge",
            testDescription: "moveToOtherChallenge"
        ),
        ReasonDescriptionExpectation(reason: .systemError(), description: "systemError", testDescription: "systemError"),
        ReasonDescriptionExpectation(
            reason: .systemError(details: "transport"),
            description: "systemError: transport",
            testDescription: "detailed systemError"
        ),
        ReasonDescriptionExpectation(reason: .unknown(), description: "unknown", testDescription: "unknown"),
        ReasonDescriptionExpectation(
            reason: .unknown(details: "fallback"),
            description: "unknown: fallback",
            testDescription: "detailed unknown"
        ),
        ReasonDescriptionExpectation(reason: .alreadyExists, description: "alreadyExists", testDescription: "alreadyExists"),
    ]
}
