import Foundation

internal final class AppConfigAPICall: APICall {
    private let coder: any JSONCoder
    let request: NetworkRequest

    internal init(apiBaseURL: URL, coder: any JSONCoder, traceParent: String?) throws {
        self.coder = coder

        var request = NetworkRequest(url: apiBaseURL.appendingPathComponent("config/app"))
        request.setMethod(.get)
        if let traceParent {
            request.setHeaderIfAbsent(name: NetworkRequest.Header.traceparent.rawValue, value: traceParent)
        }

        self.request = request
    }

    func mapHttpSuccess(_ successResponse: NetworkResponse.Success) -> APIResult<AppConfig, AppConfigFailure> {
        guard successResponse.code == 200 else {
            return .failure(mapUnhandled(successResponse.toUnexpectedStatusFail()))
        }

        do {
            let response = try coder.decodeFromString(successResponse.body, as: InternalAppAuthConfig.self)

            return .success(
                AppConfig(
                    loginIdConfig: response.loginIdConfig.map { loginIdConfig in
                        AppConfig.LoginIdConfig(type: loginIdConfig.type.toDomainModel(), regex: loginIdConfig.regex)
                    },
                    displayName: response.displayName,
                    webView: response.webView.map { webView in
                        AppConfig.WebViewConfig(
                            baseUrl: webView.baseUrl,
                            html: webView.html,
                            allowedOrigins: webView.allowedOrigins.map { Set($0) }
                        )
                    },
                    ui: response.ui.map { ui in
                        AppConfig.UIConfig(
                            default: AppConfig.UIConfig.UIThemeConfig(logoUrl: ui.default.logoUrl),
                            dark: ui.dark.map { AppConfig.UIConfig.UIThemeConfig(logoUrl: $0.logoUrl) }
                        )
                    },
                    logLevel: {
                        guard let logLevel = response.logLevel else {
                            return .warning
                        }

                        switch logLevel {
                        case .error: return .error
                        case .warning: return .warning
                        case .information: return .information
                        case .debug: return .debug
                        case .none: return .none
                        }
                    }()
                )
            )
        } catch {
            return .failure(
                mapUnhandled(
                    successResponse.toSuccessMappingFail(
                        message: "Failed to parse success response from \(successResponse.url)",
                        cause: error
                    )
                )
            )
        }
    }

    func mapHttpError(_ failResponse: NetworkResponse.Fail.HttpError) -> AppConfigFailure {
        switch failResponse.statusCode {
        case 400:
            return failResponse.mapDecodedBody(
                coder: coder,
                as: InternalBadRequestErrorResponse.self,
                unexpected: AppConfigFailure.unexpected
            ) { response in
                response.toFailure(
                    invalidArgument: { .badRequest(errorCode: $0, message: $1) },
                    unknown: { .badRequest(errorCode: $0, message: $1) }
                )
            }

        default:
            return failResponse.toUnexpectedFailure(AppConfigFailure.unexpected)
        }
    }

    func mapUnhandled(_ failResponse: NetworkResponse.Fail) -> AppConfigFailure {
        failResponse.toUnexpectedFailure(AppConfigFailure.unexpected)
    }
}
