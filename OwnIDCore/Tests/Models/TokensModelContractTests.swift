import Foundation
import Testing

@testable import OwnIDCore

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

    @Test func `Access token login ID accepts padded Base64url JWT payload`() throws {
        let token = AccessToken(
            token: [
                paddedBase64URL("{}"),
                paddedBase64URL(#"{"sub":"Email:user@example.test"}"#),
                "signature",
            ].joined(separator: ".")
        )

        let loginID = try token.loginID(coder: JSONCoderImpl(), validator: TokenLoginIDValidator())

        #expect(loginID == LoginID(id: "user@example.test", type: .email))
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
