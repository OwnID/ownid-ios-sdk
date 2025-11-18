import Foundation

extension URLRequest {
    static func defaultHeaders(supportedLanguages: OwnID.CoreSDK.Languages) -> [String: String] {
        let languagesString = supportedLanguages.rawValue.joined(separator: ",")
        var headers: [String: String] = [
            "User-Agent": OwnID.CoreSDK.UserAgentManager.shared.SDKUserAgent,
            "X-API-Version": OwnID.CoreSDK.APIVersion,
            "Accept-Language": languagesString,
            "Content-Type": "application/json"
        ]
        if let appUrl = OwnID.CoreSDK.shared.store.value.configuration?.appUrl { headers["X-OwnID-AppUrl"] = appUrl }
        return headers
    }
    
    static func request(url: OwnID.CoreSDK.ServerURL,
                        method: OwnID.CoreSDK.HTTPMethod,
                        body: Data?,
                        headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.allHTTPHeaderFields = headers

        printRequest(url: url,
                     method: method,
                     body: body,
                     headers: headers)
        
        return request
    }
    
    private static func printRequest(url: OwnID.CoreSDK.ServerURL,
                                     method: OwnID.CoreSDK.HTTPMethod,
                                     body: Data?,
                                     headers: [String: String]) {
        var headersFields = ""
        headers.forEach({ key, value in
            headersFields.append("    \(key): \(value)\n")
        })
        
        var bodyFields = ""
        if let body {
            let json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String : Any]
            json?.forEach({ key, value in
                bodyFields.append("     \(key): \(value)\n")
            })
        }

//        print("----------------\n URL: \(url)\n\n Method: \(method.rawValue)\n\n Headers:\n\(headersFields)\n Body:\n\(bodyFields)----------------\n")
    }
}

extension String {
    func extendHttpsIfNeeded() -> Self {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil {
            return trimmed
        }
        return "https://" + trimmed
    }
    
    var isBlank: Bool {
        return allSatisfy { $0.isWhitespace }
    }
}
