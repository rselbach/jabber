import Foundation

enum AppSettingKey {
    static let selectedModel = "selectedModel"
    static let selectedLanguage = "selectedLanguage"
    static let inputDeviceUID = "inputDeviceUID"
    static let outputMode = "outputMode"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeyActivationMode = "hotkeyActivationMode"
    static let pauseMediaDuringRecording = "pauseMediaDuringRecording"
    static let soundFeedbackEnabled = "soundFeedbackEnabled"
    static let historyEnabled = "historyEnabled"
    static let historyKeepsAudio = "historyKeepsAudio"
    static let historyRetention = "historyRetention"
    /// The old opt-in debug history, which always saved audio. Read once by
    /// `SettingsStore.migrateStoredValues()` and then removed.
    static let legacySaveHistoryEnabled = "saveHistoryEnabled"
    static let replacementEntries = "replacementEntries"
    static let postProcessingEnabled = "postProcessingEnabled"
    static let postProcessingProviderKind = "postProcessingProviderKind"
    static let openRouterModel = "openRouterModel"
    static let openCodeZenModel = "openCodeZenModel"
    static let didShowFirstRunSetup = "didShowFirstRunSetup"
    static let onboardingCompleted = "onboardingCompleted"
    static let lastModelMigrationNoticeKey = "lastModelMigrationNoticeKey"
    static let declinedModelMigrationNoticeKey = "declinedModelMigrationNoticeKey"
}
