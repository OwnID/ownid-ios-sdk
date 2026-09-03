import Foundation
@testable import OwnIDCore
import Testing

// Covers: MODEL-080, MODEL-090, MODEL-100
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

    @Test func `JSON value distinguishes Foundation booleans from numbers`() {
        let value = JSONValue(from: [
            "values": [
                "swiftTrue": true,
                "swiftFalse": false,
                "numberTrue": NSNumber(value: true),
                "numberFalse": NSNumber(value: false),
                "zero": NSNumber(value: 0),
                "one": NSNumber(value: 1),
                "integer": NSNumber(value: 42),
                "integralDouble": NSNumber(value: 7.0),
                "fractionalDouble": NSNumber(value: 7.5),
                "unsupported": NSDate(timeIntervalSince1970: 0),
            ] as [String: Any],
        ] as [String: Any])

        #expect(value == .dictionary([
            "values": .dictionary([
                "swiftTrue": .bool(true),
                "swiftFalse": .bool(false),
                "numberTrue": .bool(true),
                "numberFalse": .bool(false),
                "zero": .int(0),
                "one": .int(1),
                "integer": .int(42),
                "integralDouble": .int(7),
                "fractionalDouble": .double(7.5),
                "unsupported": .null,
            ]),
        ]))
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

    @Test func `Availability exposes available and diagnostic-only unavailable behavior`() {
        var events: [String] = []

        let available = Availability.available
            .onAvailable { events.append("available") }
            .onUnavailable { events.append("unexpected:\($0)") }

        switch available {
        case .available:
            break
        case .unavailable(let message):
            Issue.record("Expected available, got unavailable: \(message)")
        }

        let unavailable = Availability.unavailable("diagnostic text is intentionally not a contract")
            .onAvailable { events.append("unexpected-available") }
            .onUnavailable { message in
                #expect(!message.isEmpty)
                events.append("unavailable")
            }

        switch unavailable {
        case .available:
            Issue.record("Expected unavailable")
        case .unavailable(let message):
            #expect(!message.isEmpty)
        }
        #expect(events == ["available", "unavailable"])
    }

    @Test func `Operation result keeps success cancellation and failure values distinct`() {
        var events: [String] = []
        let failure = ResultModelFailure(message: "operation denied")

        let success = OperationResult<String, ResultModelFailure>.success("operation-ok")
            .onSuccess { events.append("success:\($0)") }
            .onCanceled { events.append("unexpected-canceled:\($0)") }
            .onError { events.append("unexpected-error:\($0.message)") }

        #expect(success.getOrNil() == "operation-ok")
        #expect(success.errorOrNil() == nil)
        #expect(success.map { "\($0):mapped" }.getOrNil() == "operation-ok:mapped")
        #expect(
            success.fold(onSuccess: { "success:\($0)" }, onCanceled: { "canceled:\($0)" }, onError: { "error:\($0.message)" })
                == "success:operation-ok"
        )

        let canceled = OperationResult<String, ResultModelFailure>.canceled(.timeout)
            .onSuccess { events.append("unexpected-success:\($0)") }
            .onCanceled { reason in
                if case .timeout = reason {
                    events.append("canceled")
                } else {
                    events.append("unexpected-canceled:\(reason)")
                }
            }
            .onError { events.append("unexpected-error:\($0.message)") }

        #expect(canceled.getOrNil() == nil)
        #expect(canceled.errorOrNil() == nil)
        #expect(canceled.map { "\($0):mapped" }.getOrNil() == nil)
        #expect(
            canceled.fold(onSuccess: { "success:\($0)" }, onCanceled: { "canceled:\($0)" }, onError: { "error:\($0.message)" })
                == "canceled:timeout"
        )

        let failed = OperationResult<String, ResultModelFailure>.failure(failure)
            .onSuccess { events.append("unexpected-success:\($0)") }
            .onCanceled { events.append("unexpected-canceled:\($0)") }
            .onError { events.append("error:\($0.message)") }

        #expect(failed.getOrNil() == nil)
        #expect(failed.errorOrNil()?.message == "operation denied")
        #expect(failed.map { "\($0):mapped" }.errorOrNil()?.message == "operation denied")
        #expect(
            failed.fold(onSuccess: { "success:\($0)" }, onCanceled: { "canceled:\($0)" }, onError: { "error:\($0.message)" })
                == "error:operation denied"
        )
        #expect(events == ["success:operation-ok", "canceled", "error:operation denied"])
    }

    @Test func `Flow result keeps success cancellation and failure values distinct`() {
        var events: [String] = []
        let failure = ResultModelFailure(message: "flow denied")

        let success = FlowResult<String, ResultModelFailure>.success("flow-ok")
            .onSuccess { events.append("success:\($0)") }
            .onCanceled { events.append("unexpected-canceled:\($0)") }
            .onError { events.append("unexpected-error:\($0.message)") }

        #expect(success.getOrNil() == "flow-ok")
        #expect(success.errorOrNil() == nil)
        #expect(success.reasonOrNil() == nil)
        #expect(success.map { "\($0):mapped" }.getOrNil() == "flow-ok:mapped")
        #expect(
            success.fold(onSuccess: { "success:\($0)" }, onCanceled: { "canceled:\($0)" }, onError: { "error:\($0.message)" })
                == "success:flow-ok"
        )

        let canceled = FlowResult<String, ResultModelFailure>.canceled(.userClose(details: "dismissed"))
            .onSuccess { events.append("unexpected-success:\($0)") }
            .onCanceled { reason in
                if case .userClose(let details) = reason {
                    #expect(details == "dismissed")
                    events.append("canceled")
                } else {
                    events.append("unexpected-canceled:\(reason)")
                }
            }
            .onError { events.append("unexpected-error:\($0.message)") }

        #expect(canceled.getOrNil() == nil)
        #expect(canceled.errorOrNil() == nil)
        expectUserClose(canceled.reasonOrNil(), details: "dismissed")
        expectUserClose(canceled.map { "\($0):mapped" }.reasonOrNil(), details: "dismissed")
        #expect(
            canceled.fold(onSuccess: { "success:\($0)" }, onCanceled: { "canceled:\($0)" }, onError: { "error:\($0.message)" })
                == "canceled:userClose: dismissed"
        )

        let failed = FlowResult<String, ResultModelFailure>.failure(failure)
            .onSuccess { events.append("unexpected-success:\($0)") }
            .onCanceled { events.append("unexpected-canceled:\($0)") }
            .onError { events.append("error:\($0.message)") }

        #expect(failed.getOrNil() == nil)
        #expect(failed.errorOrNil()?.message == "flow denied")
        #expect(failed.reasonOrNil() == nil)
        #expect(failed.map { "\($0):mapped" }.errorOrNil()?.message == "flow denied")
        #expect(
            failed.fold(onSuccess: { "success:\($0)" }, onCanceled: { "canceled:\($0)" }, onError: { "error:\($0.message)" })
                == "error:flow denied"
        )
        #expect(events == ["success:flow-ok", "canceled", "error:flow denied"])
    }

    private func expectUserClose(
        _ reason: Reason?,
        details expectedDetails: String,
        sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
    ) {
        if case .userClose(let details)? = reason {
            #expect(details == expectedDetails, sourceLocation: sourceLocation)
        } else {
            Issue.record("Expected user-close cancellation", sourceLocation: sourceLocation)
        }
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

private struct ResultModelFailure: OperationFailure, FlowFailure {
    let errorCode: ErrorCode = .unknown
    let message: String
}
