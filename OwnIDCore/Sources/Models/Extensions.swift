import Foundation

extension String {
    internal func shorten() -> String {
        if self.count <= 16 { return self }
        return "\(self.prefix(8))..[\(self.count - 16)]...\(self.suffix(8))"
    }

    internal func maskID() -> String {
        let value = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "" }
        if value.count <= 4 { return "•••" }

        let prefixLength = 2
        let suffixLength = 2
        let prefix = value.prefix(prefixLength)
        let suffix = value.suffix(suffixLength)
        let maskLength = value.count - prefixLength - suffixLength
        return "\(prefix)\(String(repeating: "•", count: maskLength))\(suffix)"
    }

    internal func maskEmail() -> String {
        guard let atIndex = self.firstIndex(of: "@") else { return self }
        let localPart = String(self[..<atIndex])
        let domainPart = String(self[atIndex...])
        if localPart.count <= 3 { return self }
        let firstChar = localPart.prefix(1)
        let lastChar = localPart.suffix(1)
        let middlePart = String(repeating: "*", count: localPart.count - 2)
        return "\(firstChar)\(middlePart)\(lastChar)\(domainPart)"
    }

    internal func maskPhoneNumber() -> String {
        let e164Pattern = "^\\+?[1-9]\\d{1,14}$"
        guard self.range(of: e164Pattern, options: .regularExpression) != nil else { return self }

        let hasPlusPrefix = self.hasPrefix("+")
        let digits = hasPlusPrefix ? String(self.dropFirst()) : self
        guard digits.count > 6 else { return self }

        let firstPart = digits.prefix(2)
        let lastPart = digits.suffix(4)
        let middlePartCount = digits.count - 6
        let middlePart = String(repeating: "*", count: middlePartCount)
        let maskedDigits = "\(firstPart)\(middlePart)\(lastPart)"
        return hasPlusPrefix ? "+\(maskedDigits)" : maskedDigits
    }

    internal func decodeBase64UrlSafe() -> Data? {
        guard let base64String = normalizedBase64UrlForDecoding() else { return nil }
        return Data(base64Encoded: base64String)
    }

    private func normalizedBase64UrlForDecoding() -> String? {
        let unpadded: Substring
        if let paddingStart = firstIndex(of: "=") {
            let padding = self[paddingStart...]
            guard padding.count <= 2, padding.allSatisfy({ $0 == "=" }), count % 4 == 0 else { return nil }
            unpadded = self[..<paddingStart]
        } else {
            unpadded = self[...]
        }

        guard unpadded.count % 4 != 1 else { return nil }
        guard unpadded.unicodeScalars.allSatisfy(Self.isBase64URLScalar(_:)) else { return nil }

        var base64String = String(unpadded)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64String += String(repeating: "=", count: (4 - base64String.count % 4) % 4)
        return base64String
    }

    private static func isBase64URLScalar(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
            || (48...57).contains(scalar.value)
            || scalar.value == 45
            || scalar.value == 95
    }
}

extension Data {
    internal static func secureRandom(count: Int = 16) -> Data {
        guard count > 0 else {
            return Data()
        }
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!)
        }
        if result == errSecSuccess {
            return data
        }
        data.withUnsafeMutableBytes { pointer in
            arc4random_buf(pointer.baseAddress!, count)
        }
        return data
    }

    internal func encodeToBase64UrlSafe(noPadding: Bool = true) -> String {
        var base64String = self.base64EncodedString()
        base64String = base64String.replacingOccurrences(of: "+", with: "-")
        base64String = base64String.replacingOccurrences(of: "/", with: "_")
        if noPadding {
            while base64String.last == "=" {
                base64String.removeLast()
            }
        }
        return base64String
    }
}
