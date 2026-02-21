import Foundation

enum AppSettingKey {
    static let selectedModel = "selectedModel"
    static let selectedLanguage = "selectedLanguage"
    static let outputMode = "outputMode"
    static let hotkeyDisplay = "hotkeyDisplay"
    static let vocabularyPrompt = "vocabularyPrompt"
}

enum AppSettings {
    @inline(__always)
    static func string(_ key: String, default defaultValue: String) -> String {
        return UserDefaults.standard.string(forKey: key) ?? defaultValue
    }

    @inline(__always)
    static func setString(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    @inline(__always)
    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        return UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    @inline(__always)
    static func setBool(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
