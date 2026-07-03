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
    case hotkeyActivationMode
    case vocabularyPrompt
    case postProcessingProviderKind
    case openRouterModel

    /// The UserDefaults key for this setting
    var key: String {
        switch self {
        case .selectedModel: return AppSettingKey.selectedModel
        case .selectedLanguage: return AppSettingKey.selectedLanguage
        case .outputMode: return AppSettingKey.outputMode
        case .hotkeyActivationMode: return AppSettingKey.hotkeyActivationMode
        case .vocabularyPrompt: return AppSettingKey.vocabularyPrompt
        case .postProcessingProviderKind: return AppSettingKey.postProcessingProviderKind
        case .openRouterModel: return AppSettingKey.openRouterModel
        }
    }
}

enum BoolSetting: Sendable {
    case didShowFirstRunSetup
    case onboardingCompleted
    case pauseMediaDuringRecording
    case saveHistoryEnabled
    case postProcessingEnabled

    var key: String {
        switch self {
        case .didShowFirstRunSetup:
            return AppSettingKey.didShowFirstRunSetup
        case .onboardingCompleted:
            return AppSettingKey.onboardingCompleted
        case .pauseMediaDuringRecording:
            return AppSettingKey.pauseMediaDuringRecording
        case .saveHistoryEnabled:
            return AppSettingKey.saveHistoryEnabled
        case .postProcessingEnabled:
            return AppSettingKey.postProcessingEnabled
        }
    }

    var `default`: Bool {
        switch self {
        case .didShowFirstRunSetup, .onboardingCompleted, .pauseMediaDuringRecording,
             .saveHistoryEnabled, .postProcessingEnabled:
            return false
        }
    }
}

enum IntSetting: Sendable {
    case hotkeyKeyCode
    case hotkeyModifiers

    var key: String {
        switch self {
        case .hotkeyKeyCode:
            return AppSettingKey.hotkeyKeyCode
        case .hotkeyModifiers:
            return AppSettingKey.hotkeyModifiers
        }
    }

    var `default`: Int {
        switch self {
        case .hotkeyKeyCode:
            return Int(HotkeyShortcut.defaultShortcut.keyCode)
        case .hotkeyModifiers:
            return Int(HotkeyShortcut.defaultShortcut.modifiers)
        }
    }
}

// MARK: - Default Values

extension TypedSetting where T == String {
    /// The default value for this string setting
    var `default`: String {
        switch self {
        case .selectedModel:
            return LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
        case .selectedLanguage:
            return Constants.defaultLanguage
        case .outputMode:
            return TypingService.OutputMode.directTyping.rawValue
        case .hotkeyActivationMode:
            return HotkeyActivationMode.defaultMode.rawValue
        case .vocabularyPrompt:
            return ""
        case .postProcessingProviderKind:
            return PostProcessingProviderKind.defaultValue.rawValue
        case .openRouterModel:
            return OpenRouterModelCatalog.defaultModelId
        }
    }
}

// MARK: - Settings Accessor

@MainActor
struct SettingsStore: Sendable {
    static let standard = SettingsStore(userDefaults: .standard)

    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    subscript(setting: TypedSetting<String>) -> String {
        get {
            let value = userDefaults.string(forKey: setting.key) ?? setting.default
            let resolvedValue: String
            switch setting {
            case .outputMode:
                resolvedValue = TypingService.migratedOutputModeRawValue(value)
            case .hotkeyActivationMode:
                resolvedValue = HotkeyActivationMode(rawValue: value)?.rawValue ?? setting.default
            case .postProcessingProviderKind:
                resolvedValue = PostProcessingProviderKind.resolve(rawValue: value).rawValue
            case .openRouterModel:
                resolvedValue = OpenRouterModelCatalog.resolveModelId(value)
            case .selectedModel, .selectedLanguage, .vocabularyPrompt:
                resolvedValue = value
            }
            if resolvedValue != value {
                userDefaults.set(resolvedValue, forKey: setting.key)
            }
            return resolvedValue
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: setting.key)
        }
    }

    subscript(setting: BoolSetting) -> Bool {
        get {
            userDefaults.object(forKey: setting.key) as? Bool ?? setting.default
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: setting.key)
        }
    }

    subscript(setting: IntSetting) -> Int {
        get {
            userDefaults.object(forKey: setting.key) as? Int ?? setting.default
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: setting.key)
        }
    }

    func remove(_ setting: TypedSetting<String>) {
        userDefaults.removeObject(forKey: setting.key)
    }

    func remove(_ setting: BoolSetting) {
        userDefaults.removeObject(forKey: setting.key)
    }

    func remove(_ setting: IntSetting) {
        userDefaults.removeObject(forKey: setting.key)
    }

    func isSet(_ setting: TypedSetting<String>) -> Bool {
        userDefaults.object(forKey: setting.key) != nil
    }

    func isSet(_ setting: BoolSetting) -> Bool {
        userDefaults.object(forKey: setting.key) != nil
    }

    func isSet(_ setting: IntSetting) -> Bool {
        userDefaults.object(forKey: setting.key) != nil
    }
}

/// Global settings accessor with type-safe getters and setters
@MainActor
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

    /// Get a boolean setting value
    static subscript(setting: BoolSetting) -> Bool {
        get {
            store[setting]
        }
        set {
            store[setting] = newValue
        }
    }

    /// Get an integer setting value
    static subscript(setting: IntSetting) -> Int {
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

    /// Remove a boolean setting value (reset to default)
    static func remove(_ setting: BoolSetting) {
        store.remove(setting)
    }

    /// Remove an integer setting value (reset to default)
    static func remove(_ setting: IntSetting) {
        store.remove(setting)
    }

    /// Check if a string setting has been explicitly set
    static func isSet(_ setting: TypedSetting<String>) -> Bool {
        store.isSet(setting)
    }

    /// Check if a boolean setting has been explicitly set
    static func isSet(_ setting: BoolSetting) -> Bool {
        store.isSet(setting)
    }

    /// Check if an integer setting has been explicitly set
    static func isSet(_ setting: IntSetting) -> Bool {
        store.isSet(setting)
    }
}
