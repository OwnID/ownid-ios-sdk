import Foundation
import Combine
import SwiftUI

extension OwnID.CoreSDK {
    public class OwnIDNetworkLogoProvider: LogoProviderProtocol {
        final class ImageCache {
            static let shared = ImageCache()
            private let cache = NSCache<NSURL, UIImage>()

            private init() { }

            func image(for url: URL) -> UIImage? {
                cache.object(forKey: url as NSURL)
            }

            func setImage(_ image: UIImage, for url: URL) {
                cache.setObject(image, forKey: url as NSURL)
            }
        }
        
        public func logo(logoURL: URL?) -> AnyPublisher<Image?, Never> {
            guard let logoURL = logoURL else {
                return Just(nil).eraseToAnyPublisher()
            }
            
            if let cachedUIImage = ImageCache.shared.image(for: logoURL) {
                let cachedImage = Image(uiImage: cachedUIImage)
                return Just(cachedImage).eraseToAnyPublisher()
            }
            
            return URLSession.shared.dataTaskPublisher(for: logoURL)
                .map { data, _ -> Image? in
                    guard let uiImage = UIImage(data: data) else { return nil }
                    
                    ImageCache.shared.setImage(uiImage, for: logoURL)
                    return Image(uiImage: uiImage)
                }
                .replaceError(with: nil)
                .eraseToAnyPublisher()
        }
    }
}
