import Foundation
import Combine

extension OwnID.CoreSDK.TranslationsSDK.Downloader {
    struct SupportedLanguages: Codable {
        let langs: [String]
    }
}

extension OwnID.CoreSDK.TranslationsSDK {
    final class Downloader {
        typealias DownloaderPublisher = AnyPublisher<(systemLanguage: String, languageJson: [String: Any]), OwnID.CoreSDK.Error>
        
        private let session: URLSession
        
        init() {
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .returnCacheDataElseLoad
            session = URLSession(configuration: config)
        }
        
        func downloadTranslations(supportedLanguages: OwnID.CoreSDK.Languages) -> DownloaderPublisher {
            Just(OwnID.CoreSDK.shared.supportedLocales ?? [])
                .setFailureType(to: OwnID.CoreSDK.Error.self)
                .eraseToAnyPublisher()
                .map { serverLanguages in LanguageMapper.matchSystemLanguage(to: serverLanguages, userDefinedLanguages: supportedLanguages.rawValue) }
                .eraseToAnyPublisher()
                .flatMap { currentUserLanguages -> DownloaderPublisher in
                    let message = "Mapped user language to the server languages. serverLanguage: \(currentUserLanguages.serverLanguage), systemLanguage: \(currentUserLanguages.systemLanguage)"
                    OwnID.CoreSDK.logger.log(level: .debug, message: message, type: OwnID.CoreSDK.TranslationsSDK.Downloader.self)
                    return self.downloadCurrentLocalizationFile(for: currentUserLanguages.serverLanguage, correspondingSystemLanguage: currentUserLanguages.systemLanguage)
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }
    }
}

private extension OwnID.CoreSDK.TranslationsSDK.Downloader {
    func valuesURL(currentLanguage: String) -> URL? {
        guard let base = OwnID.CoreSDK.shared.store.value.configuration?.i18nBaseURL else { return nil }
        return base.appendingPathComponent(currentLanguage).appendingPathComponent("mobile-sdk.json")
    }

    func downloadCurrentLocalizationFile(for currentBELanguage: String, correspondingSystemLanguage: String) -> DownloaderPublisher {
        guard let url = valuesURL(currentLanguage: currentBELanguage) else {
            OwnID.CoreSDK.logger.log(level: .warning, message: "Skip translations download: i18n base URL is unavailable", type: OwnID.CoreSDK.TranslationsSDK.Downloader.self)
            return Empty().setFailureType(to: OwnID.CoreSDK.Error.self).eraseToAnyPublisher()
        }
        var request = URLRequest(url: url)
        var headers: [String: String] = [
            "User-Agent": OwnID.CoreSDK.UserAgentManager.shared.SDKUserAgent,
            "Accept-Language": correspondingSystemLanguage
        ]
        if let appUrl = OwnID.CoreSDK.shared.store.value.configuration?.appUrl { headers["X-OwnID-AppUrl"] = appUrl }
        request.allHTTPHeaderFields = headers
        
        return session.dataTaskPublisher(for: request)
            .eraseToAnyPublisher()
            .map { $0.data }
            .compactMap {
                let result = try? JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any]
                return result
            }
            .map { (correspondingSystemLanguage, $0) }
            .mapError {
                OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: $0.localizedDescription))
            }
            .eraseToAnyPublisher()
    }
}
