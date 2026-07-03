import Foundation

/// Runtime origin policy used by WebBridge message validation.
///
/// Rules compare a message source URL against normalized HTTP(S) origins. A rule without an explicit port matches the
/// scheme's default port only, explicit ports must match exactly, DNS wildcard rules match subdomains only, and the
/// global wildcard is represented separately because it bypasses host matching.
internal struct OriginPolicy {
    internal struct Rule {
        internal let scheme: String
        internal let wildcard: Bool
        internal let host: String
        internal let port: Int?
        internal let isIPv6: Bool
    }

    internal let any: Bool
    internal let rules: [Rule]

    internal static let any = OriginPolicy(any: true, rules: [])

    internal func isAllowed(_ url: URL) -> Bool {
        if any { return true }
        guard let sourceScheme = url.scheme?.lowercased(), let sourceHost = url.host?.lowercased() else { return false }
        let sourcePort = url.port ?? Self.defaultPort(for: sourceScheme)

        for rule in rules {
            guard rule.scheme == sourceScheme else { continue }
            let expectedPort = rule.port ?? Self.defaultPort(for: rule.scheme)
            guard expectedPort == sourcePort else { continue }

            let hostMatches: Bool = {
                if rule.isIPv6 { return sourceHost == rule.host }
                if rule.wildcard { return sourceHost.hasSuffix("." + rule.host) }
                return sourceHost == rule.host
            }()
            if hostMatches { return true }
        }

        return false
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return -1
        }
    }
}

/// Normalizes WebBridge origin rules for injection metadata and runtime message checks.
///
/// Rules may be full HTTP(S) origins, schemeless host rules that default to `https`, host rules with explicit ports,
/// DNS-only wildcard rules such as `*.example.com`, bracketed IPv6 literals, or the global `*` wildcard. Paths, query
/// strings, fragments, userinfo, empty or malformed ports, trailing-dot hosts, zone-scoped IPv6 literals, and wildcard
/// rules for IP hosts are skipped before any rule becomes part of attachment metadata or runtime validation.
///
/// Page URLs are stricter about intent: they must already be absolute HTTP(S) URLs and are reduced to their origin by
/// discarding path, query, and fragment while preserving a valid explicit port.
internal enum OriginNormalizer {
    /// Result of origin rule normalization.
    ///
    /// `normalized` contains de-duplicated origin strings for injection metadata. `policy` is the runtime matcher used
    /// for message validation. `skipped` preserves the original rejected rule text so callers can log actionable
    /// diagnostics without exposing normalized guesses.
    internal struct NormalizationResult {
        internal let policy: OriginPolicy
        internal let normalized: Set<String>
        internal let skipped: [String]
    }

    private enum HostType { case dns, ipv4, ipv6 }

    /// Normalizes configured allowlist rules for WebBridge injection metadata and runtime message delivery.
    ///
    /// Invalid entries do not fail the whole set; callers decide whether an empty non-wildcard policy is a fatal
    /// attachment error.
    internal static func normalizeAllowedOriginRules(_ rawRules: Set<String>) -> NormalizationResult {
        var any = false
        var rules: [OriginPolicy.Rule] = []
        var normalized = Set<String>()
        var skipped: [String] = []

        for rawRule in rawRules {
            let trimmed = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                skipped.append(rawRule)
                continue
            }
            if trimmed == "*" {
                any = true
                normalized.insert("*")
                continue
            }
            guard let normalizedRule = normalizeAllowedOriginRuleOrNil(trimmed) else {
                skipped.append(rawRule)
                continue
            }

            rules.append(normalizedRule.rule)
            normalized.insert(normalizedRule.normalized)
        }

        return NormalizationResult(
            policy: OriginPolicy(any: any, rules: any ? [] : rules),
            normalized: normalized,
            skipped: skipped
        )
    }

    /// Extracts an HTTP(S) origin from an absolute page URL.
    ///
    /// This is used when an operation receives a concrete page URL and needs an equivalent origin rule. Relative URLs,
    /// unsupported schemes, userinfo, malformed ports, and hosts rejected by `classifyHost(_:)` return `nil`.
    internal static func origin(fromAbsolutePageURL rawURL: String) -> String? {
        let raw = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let delimiterRange = raw.range(of: "://"), delimiterRange.lowerBound > raw.startIndex else {
            return nil
        }

        let scheme = String(raw[..<delimiterRange.lowerBound]).lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }

        let remainder = String(raw[delimiterRange.upperBound...])
        guard !remainder.isEmpty else { return nil }

        return parseAuthority(
            scheme: scheme,
            authorityRaw: remainder,
            wildcard: false,
            allowPathQueryFragmentSuffix: true
        )?.normalized
    }

    private static func normalizeAllowedOriginRuleOrNil(_ rawRule: String) -> (normalized: String, rule: OriginPolicy.Rule)? {
        let withScheme = rawRule.contains("://") ? rawRule : "https://\(rawRule)"
        guard let delimiterRange = withScheme.range(of: "://"), delimiterRange.lowerBound > withScheme.startIndex else {
            return nil
        }

        let scheme = String(withScheme[..<delimiterRange.lowerBound]).lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }

        let authorityRaw = String(withScheme[delimiterRange.upperBound...])
        let wildcard = authorityRaw.hasPrefix("*.")
        let authority = wildcard ? String(authorityRaw.dropFirst(2)) : authorityRaw
        guard !authority.isEmpty, !authority.contains("*") else { return nil }

        guard
            let parsed = parseAuthority(
                scheme: scheme,
                authorityRaw: authority,
                wildcard: wildcard,
                allowPathQueryFragmentSuffix: false
            )
        else {
            return nil
        }

        return (
            normalized: parsed.normalized,
            rule: OriginPolicy.Rule(
                scheme: scheme,
                wildcard: wildcard,
                host: parsed.matchHost,
                port: parsed.port,
                isIPv6: parsed.isIPv6
            )
        )
    }

    private static func parseAuthority(
        scheme: String,
        authorityRaw: String,
        wildcard: Bool,
        allowPathQueryFragmentSuffix: Bool
    ) -> (normalized: String, matchHost: String, port: Int?, isIPv6: Bool)? {
        let authorityPart = authorityRaw.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let authority = String(authorityPart)
        guard !authority.isEmpty else { return nil }
        if !allowPathQueryFragmentSuffix, authorityPart.count != authorityRaw.count { return nil }
        guard !authority.hasSuffix(":"), !authority.contains("@") else { return nil }
        guard let parsedAuthority = parseHostAndPort(authority) else { return nil }

        let host = parsedAuthority.host
        guard let hostType = classifyHost(host) else { return nil }
        if wildcard && hostType != .dns { return nil }

        let normalizedHost: String
        let matchHost: String
        switch hostType {
        case .dns, .ipv4:
            normalizedHost = host.lowercased()
            matchHost = normalizedHost
        case .ipv6:
            let rawIPv6 = String(host.dropFirst().dropLast()).lowercased()
            normalizedHost = "[\(rawIPv6)]"
            matchHost = rawIPv6
        }

        let portPart = parsedAuthority.port.map { ":\($0)" } ?? ""
        return (
            normalized: "\(scheme)://\(wildcard ? "*." : "")\(normalizedHost)\(portPart)",
            matchHost: matchHost,
            port: parsedAuthority.port,
            isIPv6: hostType == .ipv6
        )
    }

    private static func parseHostAndPort(_ authority: String) -> (host: String, port: Int?)? {
        if authority.hasPrefix("[") {
            guard let bracketEnd = authority.firstIndex(of: "]") else { return nil }
            let host = String(authority[...bracketEnd])
            let remainder = authority[authority.index(after: bracketEnd)...]
            if remainder.isEmpty { return (host, nil) }

            guard remainder.first == ":" else { return nil }
            let portString = String(remainder.dropFirst())
            guard !portString.isEmpty, portString.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
                return nil
            }
            guard let port = Int(portString), (1...65535).contains(port) else { return nil }
            return (host, port)
        }

        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let host = String(parts[0])
        guard !host.isEmpty else { return nil }
        if parts.count == 1 { return (host, nil) }

        let portString = String(parts[1])
        guard !portString.isEmpty, portString.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
            return nil
        }
        guard let port = Int(portString), (1...65535).contains(port) else { return nil }
        return (host, port)
    }

    private static func classifyHost(_ host: String) -> HostType? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHost == host, !trimmedHost.isEmpty else { return nil }

        if trimmedHost.hasPrefix("[") && trimmedHost.hasSuffix("]") {
            let value = String(trimmedHost.dropFirst().dropLast())
            if value.isEmpty || value.contains("%") { return nil }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "[\(value)]"
            guard components.url != nil, components.host?.caseInsensitiveCompare("[\(value)]") == .orderedSame else {
                return nil
            }
            return .ipv6
        }

        if trimmedHost.contains(":") || trimmedHost.hasSuffix(".") { return nil }
        if trimmedHost.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil {
            return isValidIPv4(trimmedHost) ? .ipv4 : nil
        }
        if isValidIPv4(trimmedHost) { return .ipv4 }
        return isValidDNSHostname(trimmedHost) ? .dns : nil
    }

    private static func isValidIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            let value = String(part)
            if value.range(of: #"^\d{1,3}$"#, options: .regularExpression) == nil { return false }
            if value.count > 1 && value.hasPrefix("0") { return false }
            guard let intValue = Int(value), (0...255).contains(intValue) else { return false }
            return true
        }
    }

    private static func isValidDNSHostname(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized.isEmpty || normalized.count > 253 { return false }
        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        if labels.contains(where: \.isEmpty) { return false }
        return labels.allSatisfy { label in
            String(label).range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
        }
    }
}
