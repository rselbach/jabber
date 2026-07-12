import Foundation

enum AppSettingKey {
    static let selectedModel = "selectedModel"
    static let selectedLanguage = "selectedLanguage"
    static let outputMode = "outputMode"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeyActivationMode = "hotkeyActivationMode"
    static let pauseMediaDuringRecording = "pauseMediaDuringRecording"
    static let soundFeedbackEnabled = "soundFeedbackEnabled"
    static let saveHistoryEnabled = "saveHistoryEnabled"
    static let vocabularyPrompt = "vocabularyPrompt"
    static let replacementEntries = "replacementEntries"
    static let postProcessingEnabled = "postProcessingEnabled"
    static let postProcessingProviderKind = "postProcessingProviderKind"
    static let openRouterModel = "openRouterModel"
    static let didShowFirstRunSetup = "didShowFirstRunSetup"
    static let onboardingCompleted = "onboardingCompleted"
    static let lastModelMigrationNoticeKey = "lastModelMigrationNoticeKey"
    static let declinedModelMigrationNoticeKey = "declinedModelMigrationNoticeKey"
}
