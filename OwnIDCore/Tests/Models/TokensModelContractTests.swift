import Foundation
import Testing

@testable import OwnIDCore

// Covers: MODEL-040
struct TokensModelContractTests {
    private let modelJSON = ModelJSON()

    @Test func `Access token Codable preserves raw token value`() throws {
        let token = AccessToken(token: "header.payload.signature")

        #expect(token.token == "header.payload.signature")
        #expect(try modelJSON.string(encoding: token) == #"{"token":"header.payload.signature"}"#)

        let decoded = try modelJSON.decoder.decode(AccessToken.self, from: Data(#"{"token":"decoded-token","extra":"ignored"}"#.utf8))

        #expect(decoded == AccessToken(token: "decoded-token"))
    }

    @Test func `Proof token Codable preserves raw token value`() throws {
        let token = ProofToken(token: "proof-token-value")

        #expect(token.token == "proof-token-value")
        #expect(try modelJSON.string(encoding: token) == #"{"token":"proof-token-value"}"#)

        let decoded = try modelJSON.decoder.decode(ProofToken.self, from: Data(#"{"token":"decoded-proof","extra":"ignored"}"#.utf8))

        #expect(decoded == ProofToken(token: "decoded-proof"))
    }

    @Test func `Token descriptions shorten long raw values`() {
        let rawToken = "1234567890ABCDEFGHIJ"

        #expect(AccessToken(token: rawToken).description == "AccessToken(token: 12345678..[4]...CDEFGHIJ)")
        #expect(ProofToken(token: rawToken).description == "ProofToken(token: 12345678..[4]...CDEFGHIJ)")
    }

    @Test func `Access or proof token keeps token kind in equality and hashing`() {
        let accessToken = AccessOrProofToken.accessToken(AccessToken(token: "same-token"))
        let proofToken = AccessOrProofToken.proofToken(ProofToken(token: "same-token"))

        #expect(accessToken == .accessToken(AccessToken(token: "same-token")))
        #expect(proofToken == .proofToken(ProofToken(token: "same-token")))
        #expect(accessToken != proofToken)
        #expect(Set([accessToken, proofToken]).count == 2)
    }

    @Test func `Access token login ID requires three nonempty unpadded Base64url segments`() throws {
        let payload = Data(#"{"sub":"Email:user@example.test"}"#.utf8).encodeToBase64UrlSafe()
        let validToken = AccessToken(token: "header.\(payload).signature")

        let loginID = try validToken.loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())
        #expect(loginID == LoginID(id: "user@example.test", type: .email))

        var invalidTokens = [
            "",
            "header",
            "header.\(payload)",
            "header.\(payload).signature.extra",
            ".\(payload).signature",
            "header..signature",
            "header.\(payload).",
        ]
        for forbidden in ["=", " ", "+", "/", "*"] {
            invalidTokens.append("head\(forbidden)er.\(payload).signature")
            invalidTokens.append("header.\(payload)\(forbidden).signature")
            invalidTokens.append("header.\(payload).sign\(forbidden)ature")
        }

        for token in invalidTokens {
            #expect(throws: TokenError.self) {
                _ = try AccessToken(token: token).loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())
            }
        }
    }

    @Test func `Access token login ID accepts actual string subjects`() throws {
        let cases: [(payload: String, expected: LoginID)] = [
            (#"{"sub":"null"}"#, LoginID(id: "null", type: .email)),
            (#"{"sub":"123"}"#, LoginID(id: "123", type: .email)),
            (#"{"sub":"true"}"#, LoginID(id: "true", type: .email)),
            (
                #"{"sub":"Email:\u03b4\u03bf\u03ba\u03b9\u03bc\u03ae@example.test"}"#,
                LoginID(id: "δοκιμή@example.test", type: .email)
            ),
        ]

        for testCase in cases {
            let loginID = try accessToken(payload: testCase.payload).loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())

            #expect(loginID == testCase.expected)
        }
    }

    @Test func `Access token login ID rejects non-string subjects`() {
        for subject in ["null", "123", "true", "{}", "[]"] {
            #expect(throws: TokenError.self) {
                _ = try accessToken(payload: #"{"sub":\#(subject)}"#)
                    .loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())
            }
        }
    }

    @Test func `Access token login ID rejects blank subjects as invalid arguments without trimming nonblank subjects`() throws {
        for subject in [" ", "\t", "\n", "\u{00A0}"] {
            let encodedSubject = try modelJSON.string(encoding: subject)
            do {
                _ = try accessToken(payload: #"{"sub":\#(encodedSubject)}"#)
                    .loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())
                Issue.record("Expected whitespace-only subject to fail")
            } catch {
                #expect(error.errorCode == .invalidArgument)
            }
        }

        let subject = " user@example.test "
        let encodedSubject = try modelJSON.string(encoding: subject)
        let loginID = try accessToken(payload: #"{"sub":\#(encodedSubject)}"#)
            .loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())

        #expect(loginID == LoginID(id: subject, type: .email))
    }

    private func accessToken(payload: String) -> AccessToken {
        AccessToken(token: "header.\(Data(payload.utf8).encodeToBase64UrlSafe()).signature")
    }
}

private struct TokenLoginIDValidator: LoginIDValidator {
    func determineLoginIDType(loginID: String) throws(LoginIDValidationError) -> LoginIDType {
        .email
    }

    func validate(_ loginID: LoginID) throws(LoginIDValidationError) -> LoginID {
        loginID
    }
}
