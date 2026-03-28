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
        case .selectedModel: return "selectedModel"
        case .selectedLanguage: return "selectedLanguage"
        case .outputMode: return "outputMode"
        case .hotkeyDisplay: return "hotkeyDisplay"
        case .vocabularyPrompt: return "vocabularyPrompt"
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

/// Global settings accessor with type-safe getters and setters
enum TypedSettings {
    /// Get a string setting value
    static subscript(setting: TypedSetting<String>) -> String {
        get {
            UserDefaults.standard.string(forKey: setting.key) ?? setting.default
        }
        set {
            UserDefaults.standard.set(newValue, forKey: setting.key)
        }
    }
    
    /// Remove a string setting value (reset to default)
    static func remove(_ setting: TypedSetting<String>) {
        UserDefaults.standard.removeObject(forKey: setting.key)
    }
    
    /// Check if a string setting has been explicitly set
    static func isSet(_ setting: TypedSetting<String>) -> Bool {
        UserDefaults.standard.object(forKey: setting.key) != nil
    }
}
