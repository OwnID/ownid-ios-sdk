import Foundation

class OwnIDCoreSDK { }

extension Bundle {
    static let resourceBundle: Bundle = {
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: OwnIDCoreSDK.self).resourceURL,
        ]
        
        let bundleNames = ["OwnIDCoreSDK", "OwnID_OwnIDCoreSDK"]
        for bundleName in bundleNames {
            for candidate in candidates {
                let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
                if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                    return bundle
                }
            }
        }
        
        return Bundle(for: OwnIDCoreSDK.self)
    }()
}
