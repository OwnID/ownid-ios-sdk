import Foundation
import Testing

@testable import OwnIDCore

struct WebBridgeOriginContractTests {

    @Test func `Allowed origin rules normalize supported forms and track rejected input`() {
        let result = OriginNormalizer.normalizeAllowedOriginRules([
            " Example.COM ",
            "http://LOCALHOST:8080",
            "*.Example.com",
            "https://[2001:DB8::1]",
            "https://bad.example/path",
            "https://example.com:",
            "ftp://example.com",
            "",
        ])

        #expect(
            result.normalized == [
                "https://example.com",
                "http://localhost:8080",
                "https://*.example.com",
                "https://[2001:db8::1]",
            ]
        )
        #expect(
            Set(result.skipped) == [
                "https://bad.example/path",
                "https://example.com:",
                "ftp://example.com",
                "",
            ]
        )
        #expect(!(result.policy.any))
    }

    @Test(arguments: OriginPolicyMatchCase.all)
    func `Origin policy matches scheme host wildcard and port rules`(_ testCase: OriginPolicyMatchCase) throws {
        let policy = OriginNormalizer.normalizeAllowedOriginRules([
            "example.com",
            "*.example.com",
            "http://localhost:8080",
            "https://[2001:db8::1]",
        ]).policy
        let url = try #require(URL(string: testCase.url))

        #expect(policy.isAllowed(url) == testCase.allowed)
    }

    @Test func `Global wildcard rule allows any URL and suppresses specific rules`() throws {
        let result = OriginNormalizer.normalizeAllowedOriginRules([
            "*",
            "https://example.com",
        ])

        #expect(result.policy.any)
        #expect(result.policy.rules.isEmpty)
        #expect(result.normalized == ["*", "https://example.com"])
        #expect(result.policy.isAllowed(try #require(URL(string: "custom-scheme:value"))))
    }

    @Test(arguments: AbsolutePageOriginCase.all)
    func `Absolute page URL origin requires HTTP or HTTPS and strips suffixes`(_ testCase: AbsolutePageOriginCase) {
        #expect(OriginNormalizer.origin(fromAbsolutePageURL: testCase.rawURL) == testCase.origin)
    }
}

struct OriginPolicyMatchCase: CustomStringConvertible, Sendable {
    let url: String
    let allowed: Bool

    var description: String { "\(allowed ? "allows" : "rejects") \(url)" }

    static let all = [
        OriginPolicyMatchCase(url: "https://example.com/account", allowed: true),
        OriginPolicyMatchCase(url: "https://login.example.com/callback", allowed: true),
        OriginPolicyMatchCase(url: "http://localhost:8080/page", allowed: true),
        OriginPolicyMatchCase(url: "https://[2001:db8::1]/page", allowed: true),
        OriginPolicyMatchCase(url: "http://example.com/account", allowed: false),
        OriginPolicyMatchCase(url: "https://example.com:444/account", allowed: false),
        OriginPolicyMatchCase(url: "https://notexample.com/callback", allowed: false),
        OriginPolicyMatchCase(url: "https://[2001:db8::2]/page", allowed: false),
    ]
}

struct AbsolutePageOriginCase: CustomStringConvertible, Sendable {
    let rawURL: String
    let origin: String?

    var description: String { rawURL }

    static let all = [
        AbsolutePageOriginCase(rawURL: " HTTPS://Example.com:8443/path?query#fragment ", origin: "https://example.com:8443"),
        AbsolutePageOriginCase(rawURL: "http://[2001:db8::1]/path", origin: "http://[2001:db8::1]"),
        AbsolutePageOriginCase(rawURL: "/relative/path", origin: nil),
        AbsolutePageOriginCase(rawURL: "ownid://example.com/path", origin: nil),
        AbsolutePageOriginCase(rawURL: "https://user:pass@example.com/path", origin: nil),
        AbsolutePageOriginCase(rawURL: "https://example.com:/path", origin: nil),
    ]
}
