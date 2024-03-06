import Foundation

extension OwnID.CoreSDK.TranslationsSDK {
    final class RuntimeLocalizableSaver {
        private enum Constants {
            static let currentLanguageKey = "currentLanguageKey"
            static let defaultFileName = "Localizable"
            static let slash = "/"
            static let jsonExtension = ".json"
            static let platformSuffix = "-ios"
        }
        
        typealias LanguageKey = String
        typealias LanguageJson = Dictionary<String, Any>
        
        private static let rootFolderName = "\(OwnID.CoreSDK.TranslationsSDK.self)"
        private let fileManager = FileManager.default
        private var currentLanguageKey: LanguageKey? {
            get {
                UserDefaults.standard.string(forKey: Constants.currentLanguageKey)
            } set {
                UserDefaults.standard.set(newValue, forKey: Constants.currentLanguageKey)
            }
        }
        
        var isRTLLanguage: Bool {
            (currentLanguageKey == "he" || currentLanguageKey == "ar") ? true : false
        }
        
        private lazy var rootFolderPath: String = {
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            let bundlePath = documentsPath + Constants.slash + RuntimeLocalizableSaver.rootFolderName
            return bundlePath
        }()
        
        init() {
            try? createRootDirectoryIfNeeded()
        }
        
        func save(languageKey: LanguageKey, languageJson: LanguageJson) throws {
            try write(languageKey: languageKey, languageJson: languageJson)
            
            currentLanguageKey = languageKey
        }
        
        func localizedString(for keys: [String]) -> String? {
            if let currentLanguageKey {
                do {
                    let filePath = rootFolderPath + "\(Constants.slash)\(currentLanguageKey)\(Constants.jsonExtension)"
                    let fileURL = URL(fileURLWithPath: filePath)
                    let fileData = try Data(contentsOf: fileURL)
                    let jsonObject = try JSONSerialization.jsonObject(with: fileData, options: [])
                    if let json = jsonObject as? [String: Any] {
                        var currentObject: Any? = json
                        var keys = keys
                        let targetKey = keys.removeLast()
                        
                        for key in keys {
                            if let subJson = currentObject as? [String: Any], let value = subJson[key] {
                                currentObject = value
                            } else {
                                return findInUpperLevel(keys: keys)
                            }
                        }
                        
                        if let subJson = currentObject as? [String: Any] {
                            if let value = subJson[targetKey] as? String {
                                return value
                            } else if let value = subJson[targetKey + Constants.platformSuffix] as? String {
                                return value
                            } else {
                                return findInUpperLevel(keys: keys)
                            }
                        } else {
                            return findInUpperLevel(keys: keys)
                        }
                        
                        func findInUpperLevel(keys: [String]) -> String? {
                            var shorterKeys = Array(keys.dropLast())
                            shorterKeys.append(targetKey)
                            if shorterKeys.count > 1 {
                                return localizedString(for: shorterKeys)
                            }
                            return nil
                        }
                    }
                } catch {
                    let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription))
                    OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self).log()
                }
            }
            
            return nil
        }
    }
}

private extension OwnID.CoreSDK.TranslationsSDK.RuntimeLocalizableSaver {
    func createRootDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: rootFolderPath) {
            do {
                try fileManager.createDirectory(atPath: rootFolderPath, withIntermediateDirectories: true)
            } catch let error {
                let error = OwnID.CoreSDK.Error.userError(errorModel: OwnID.CoreSDK.UserErrorModel(message: error.localizedDescription))
                OwnID.CoreSDK.ErrorWrapper(error: error, type: Self.self).log()
                throw error
            }
        }
    }
    
    func write(languageKey: LanguageKey, languageJson: LanguageJson) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: languageJson, options: .prettyPrinted)
        let filePath = rootFolderPath + "/\(languageKey)\(Constants.jsonExtension)"
        if fileManager.fileExists(atPath: filePath) {
            try? fileManager.removeItem(atPath: filePath)
        }
        fileManager.createFile(atPath: filePath, contents: jsonData)
        
        let message = "Wrote bundle strings to languageKey \(languageKey)"
        OwnID.CoreSDK.logger.log(level: .debug, message: message, type: OwnID.CoreSDK.TranslationsSDK.RuntimeLocalizableSaver.self)
    }
}
