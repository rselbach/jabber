import Foundation

/// Type-safe wrapper for UserDefaults storage.
/// Eliminates string-typed keys and provides compile-time safety.
///
/// Example usage:
/// ```swift
/// let language = TypedSettings[.selectedLanguage]
/// TypedSettings[.vocabularyPrompt] = "medical terms"
/// ```
enum TypedSetting<T>: Sendable {
    case selectedModel
    case selectedLanguage
    case outputMode
    case hotkeyDisplay
    case vocabularyPrompt
    
    /// The UserDefaults key for this setting
    var key: String {
        switch self {
        case .selectedModel: return AppSettingKey.selectedModel
        case .selectedLanguage: return AppSettingKey.selectedLanguage
        case .outputMode: return AppSettingKey.outputMode
        case .hotkeyDisplay: return AppSettingKey.hotkeyDisplay
        case .vocabularyPrompt: return AppSettingKey.vocabularyPrompt
        }
    }
}

// MARK: - Default Values

extension TypedSetting where T == String {
    /// The default value for this string setting
    var `default`: String {
        switch self {
        case .selectedModel:
            return AppMode.baseModelId
        case .selectedLanguage:
            return Constants.defaultLanguage
        case .outputMode:
            return "paste"
        case .hotkeyDisplay:
            return "⌥ Space"
        case .vocabularyPrompt:
            return ""
        }
    }
}

// MARK: - Settings Accessor

struct SettingsStore {
    static let standard = SettingsStore(userDefaults: .standard)

    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    subscript(setting: TypedSetting<String>) -> String {
        get {
            userDefaults.string(forKey: setting.key) ?? setting.default
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: setting.key)
        }
    }

    func remove(_ setting: TypedSetting<String>) {
        userDefaults.removeObject(forKey: setting.key)
    }

    func isSet(_ setting: TypedSetting<String>) -> Bool {
        userDefaults.object(forKey: setting.key) != nil
    }
}

/// Global settings accessor with type-safe getters and setters
enum TypedSettings {
    private static let store = SettingsStore.standard

    /// Get a string setting value
    static subscript(setting: TypedSetting<String>) -> String {
        get {
            store[setting]
        }
        set {
            store[setting] = newValue
        }
    }
    
    /// Remove a string setting value (reset to default)
    static func remove(_ setting: TypedSetting<String>) {
        store.remove(setting)
    }
    
    /// Check if a string setting has been explicitly set
    static func isSet(_ setting: TypedSetting<String>) -> Bool {
        store.isSet(setting)
    }
}
