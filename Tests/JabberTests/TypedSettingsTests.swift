import Carbon
import XCTest
@testable import Jabber
import Foundation

@MainActor
final class TypedSettingsTests: XCTestCase {
    private var settings: SettingsStore!
    private var userDefaultsSuiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        userDefaultsSuiteName = "JabberTests.TypedSettings.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName))
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        settings = SettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        if let userDefaultsSuiteName, let userDefaults {
            userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        }
        settings = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        try await super.tearDown()
    }

    func testDefaultValues() {
        XCTAssertEqual(settings[.selectedModel], LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage), "Default model should match the default language recommendation")
        XCTAssertEqual(settings[.selectedLanguage], Constants.defaultLanguage, "Default language should match system")
        XCTAssertEqual(settings[.outputMode], TypingService.OutputMode.directTyping.rawValue)
        XCTAssertEqual(settings[.hotkeyActivationMode], HotkeyActivationMode.defaultMode.rawValue)
        XCTAssertEqual(settings[.vocabularyPrompt], "", "Default vocabulary should be empty")
        XCTAssertEqual(settings[.replacementEntries], "", "Default replacement entries should be empty JSON string")
        XCTAssertEqual(settings.replacementEntries, [], "Default replacement entries array should be empty")
        XCTAssertEqual(settings[.postProcessingProviderKind], PostProcessingProviderKind.defaultValue.rawValue)
        XCTAssertEqual(settings[.openRouterModel], OpenRouterModelCatalog.defaultModelId)
        XCTAssertEqual(settings[.lastModelMigrationNoticeKey], "")
        XCTAssertEqual(settings[.declinedModelMigrationNoticeKey], "")
    }

    func testPostProcessingProviderKindDefaultsAndPersistence() {
        XCTAssertEqual(settings[.postProcessingProviderKind], "appleIntelligence")
        XCTAssertFalse(settings.isSet(.postProcessingProviderKind))

        settings[.postProcessingProviderKind] = PostProcessingProviderKind.openRouter.rawValue
        XCTAssertEqual(settings[.postProcessingProviderKind], "openRouter")
        XCTAssertTrue(settings.isSet(.postProcessingProviderKind))

        settings.remove(.postProcessingProviderKind)
        XCTAssertEqual(settings[.postProcessingProviderKind], PostProcessingProviderKind.defaultValue.rawValue)
        XCTAssertFalse(settings.isSet(.postProcessingProviderKind))
    }

    func testInvalidStoredProviderKindMigratesToDefault() {
        userDefaults.set("changnesia", forKey: AppSettingKey.postProcessingProviderKind)

        // Migration is an explicit launch-time pass now (getters are pure and
        // no longer write stale-resolved values back to storage).
        settings.migrateStoredValues()

        XCTAssertEqual(settings[.postProcessingProviderKind], PostProcessingProviderKind.defaultValue.rawValue)
        XCTAssertEqual(
            userDefaults.string(forKey: AppSettingKey.postProcessingProviderKind),
            PostProcessingProviderKind.defaultValue.rawValue
        )
    }

    func testOpenRouterModelDefaultsAndPersistence() {
        XCTAssertEqual(settings[.openRouterModel], OpenRouterModelCatalog.defaultModelId)
        XCTAssertFalse(settings.isSet(.openRouterModel))

        let slug = "~anthropic/claude-haiku-latest"
        settings[.openRouterModel] = slug
        XCTAssertEqual(settings[.openRouterModel], slug)
        XCTAssertTrue(settings.isSet(.openRouterModel))

        settings.remove(.openRouterModel)
        XCTAssertEqual(settings[.openRouterModel], OpenRouterModelCatalog.defaultModelId)
        XCTAssertFalse(settings.isSet(.openRouterModel))
    }

    func testInvalidStoredOpenRouterModelMigratesToDefault() {
        userDefaults.set("openai/gpt-4o", forKey: AppSettingKey.openRouterModel)

        settings.migrateStoredValues()

        XCTAssertEqual(settings[.openRouterModel], OpenRouterModelCatalog.defaultModelId)
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.openRouterModel), OpenRouterModelCatalog.defaultModelId)
    }

    func testLegacyPasteOutputModeMigratesToDirectTyping() {
        userDefaults.set("paste", forKey: AppSettingKey.outputMode)

        settings.migrateStoredValues()

        XCTAssertEqual(settings[.outputMode], TypingService.OutputMode.directTyping.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.outputMode), TypingService.OutputMode.directTyping.rawValue)
    }

    func testInvalidHotkeyActivationModeMigratesToDefault() {
        userDefaults.set("changnesia", forKey: AppSettingKey.hotkeyActivationMode)

        settings.migrateStoredValues()

        XCTAssertEqual(settings[.hotkeyActivationMode], HotkeyActivationMode.defaultMode.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.hotkeyActivationMode), HotkeyActivationMode.defaultMode.rawValue)
    }

    /// A read API must not mutate storage. The subscript getter resolves a
    /// stale stored value to its canonical form WITHOUT writing it back; the
    /// explicit `migrateStoredValues()` pass owns the write. Guards against a
    /// regression to the old getter side effect, which churned SwiftUI body
    /// evaluation ("modifying state during view update").
    func testGetterDoesNotWriteToUserDefaultsForMigratableSetting() {
        userDefaults.set("changnesia", forKey: AppSettingKey.postProcessingProviderKind)

        let before = userDefaults.string(forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(before, "changnesia")

        // Reading resolves to the default but must NOT persist it.
        let resolved = settings[.postProcessingProviderKind]
        XCTAssertEqual(resolved, PostProcessingProviderKind.defaultValue.rawValue)

        // The stored raw value is unchanged: a getter-triggered write would
        // have replaced "changnesia" with "appleIntelligence".
        XCTAssertEqual(
            userDefaults.string(forKey: AppSettingKey.postProcessingProviderKind),
            "changnesia",
            "subscript getter must not mutate UserDefaults"
        )
    }

    /// The migration pass is idempotent: running it again after a value is
    /// already canonical writes nothing, so re-running each launch is a no-op.
    func testMigrateStoredValuesIsIdempotent() {
        userDefaults.set("changnesia", forKey: AppSettingKey.postProcessingProviderKind)
        settings.migrateStoredValues()
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.postProcessingProviderKind), "appleIntelligence")

        // Second pass: already canonical, no write (and no spurious change).
        settings.migrateStoredValues()
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.postProcessingProviderKind), "appleIntelligence")
    }

    func testSettingAndGettingValues() {
        // Set custom values
        settings[.selectedModel] = "medium"
        settings[.selectedLanguage] = "en"
        settings[.vocabularyPrompt] = "medical terminology"

        // Verify they're stored
        XCTAssertEqual(settings[.selectedModel], "medium")
        XCTAssertEqual(settings[.selectedLanguage], "en")
        XCTAssertEqual(settings[.vocabularyPrompt], "medical terminology")
    }

    func testIsSetReturnsFalseForUnsetValues() {
        // Ensure settings are not set
        settings.remove(.selectedModel)

        // isSet should return false for unset values
        XCTAssertFalse(settings.isSet(.selectedModel), "isSet should return false for removed setting")
    }

    func testIsSetReturnsTrueForSetValues() {
        settings[.selectedModel] = "large"

        XCTAssertTrue(settings.isSet(.selectedModel), "isSet should return true for explicitly set value")
    }

    func testRemoveResetsToDefault() {
        let defaultModel = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
        let nonDefaultModel = AppMode.qwen3ModelId

        // Set a non-default value
        settings[.selectedModel] = nonDefaultModel
        XCTAssertEqual(settings[.selectedModel], nonDefaultModel)

        // Remove it
        settings.remove(.selectedModel)

        // Should return to default
        XCTAssertEqual(settings[.selectedModel], defaultModel)
        XCTAssertFalse(settings.isSet(.selectedModel))
    }

    func testBoolSettingDefaultsAndPersistence() {
        XCTAssertFalse(settings[.didShowFirstRunSetup])
        XCTAssertFalse(settings[.onboardingCompleted])
        XCTAssertFalse(settings[.pauseMediaDuringRecording])
        XCTAssertFalse(settings[.saveHistoryEnabled])
        XCTAssertFalse(settings[.postProcessingEnabled])
        XCTAssertTrue(settings[.soundFeedbackEnabled])
        XCTAssertFalse(settings.isSet(.didShowFirstRunSetup))
        XCTAssertFalse(settings.isSet(.onboardingCompleted))
        XCTAssertFalse(settings.isSet(.pauseMediaDuringRecording))
        XCTAssertFalse(settings.isSet(.saveHistoryEnabled))
        XCTAssertFalse(settings.isSet(.postProcessingEnabled))
        XCTAssertFalse(settings.isSet(.soundFeedbackEnabled))

        settings[.didShowFirstRunSetup] = true
        settings[.onboardingCompleted] = true
        settings[.pauseMediaDuringRecording] = true
        settings[.saveHistoryEnabled] = true
        settings[.postProcessingEnabled] = true
        settings[.soundFeedbackEnabled] = false

        XCTAssertFalse(settings[.soundFeedbackEnabled])
        XCTAssertTrue(settings.isSet(.soundFeedbackEnabled))
        XCTAssertTrue(settings[.didShowFirstRunSetup])
        XCTAssertTrue(settings[.onboardingCompleted])
        XCTAssertTrue(settings[.pauseMediaDuringRecording])
        XCTAssertTrue(settings[.saveHistoryEnabled])
        XCTAssertTrue(settings[.postProcessingEnabled])
        XCTAssertTrue(settings.isSet(.didShowFirstRunSetup))
        XCTAssertTrue(settings.isSet(.onboardingCompleted))
        XCTAssertTrue(settings.isSet(.pauseMediaDuringRecording))
        XCTAssertTrue(settings.isSet(.saveHistoryEnabled))
        XCTAssertTrue(settings.isSet(.postProcessingEnabled))
    }

    func testBoolSettingRemoveResetsToDefault() {
        settings[.didShowFirstRunSetup] = true
        settings[.onboardingCompleted] = true
        settings[.pauseMediaDuringRecording] = true
        settings[.saveHistoryEnabled] = true
        settings[.postProcessingEnabled] = true
        XCTAssertTrue(settings[.didShowFirstRunSetup])
        XCTAssertTrue(settings[.onboardingCompleted])
        XCTAssertTrue(settings[.pauseMediaDuringRecording])
        XCTAssertTrue(settings[.saveHistoryEnabled])
        XCTAssertTrue(settings[.postProcessingEnabled])

        settings[.soundFeedbackEnabled] = false
        XCTAssertFalse(settings[.soundFeedbackEnabled])

        settings.remove(.didShowFirstRunSetup)
        settings.remove(.onboardingCompleted)
        settings.remove(.pauseMediaDuringRecording)
        settings.remove(.saveHistoryEnabled)
        settings.remove(.postProcessingEnabled)
        settings.remove(.soundFeedbackEnabled)
        XCTAssertTrue(settings[.soundFeedbackEnabled])

        XCTAssertFalse(settings[.didShowFirstRunSetup])
        XCTAssertFalse(settings[.onboardingCompleted])
        XCTAssertFalse(settings[.pauseMediaDuringRecording])
        XCTAssertFalse(settings[.saveHistoryEnabled])
        XCTAssertFalse(settings[.postProcessingEnabled])
        XCTAssertFalse(settings.isSet(.didShowFirstRunSetup))
        XCTAssertFalse(settings.isSet(.onboardingCompleted))
        XCTAssertFalse(settings.isSet(.pauseMediaDuringRecording))
        XCTAssertFalse(settings.isSet(.saveHistoryEnabled))
        XCTAssertFalse(settings.isSet(.postProcessingEnabled))
    }

    func testIntSettingDefaultsAndPersistence() {
        XCTAssertEqual(settings[.hotkeyKeyCode], Int(HotkeyShortcut.defaultShortcut.keyCode))
        XCTAssertEqual(settings[.hotkeyModifiers], Int(HotkeyShortcut.defaultShortcut.modifiers))
        XCTAssertFalse(settings.isSet(.hotkeyKeyCode))

        settings[.hotkeyKeyCode] = 42
        settings[.hotkeyModifiers] = 2048

        XCTAssertEqual(settings[.hotkeyKeyCode], 42)
        XCTAssertEqual(settings[.hotkeyModifiers], 2048)
        XCTAssertTrue(settings.isSet(.hotkeyKeyCode))
    }

    func testIntSettingRemoveResetsToDefault() {
        settings[.hotkeyKeyCode] = 42
        XCTAssertEqual(settings[.hotkeyKeyCode], 42)

        settings.remove(.hotkeyKeyCode)

        XCTAssertEqual(settings[.hotkeyKeyCode], Int(HotkeyShortcut.defaultShortcut.keyCode))
        XCTAssertFalse(settings.isSet(.hotkeyKeyCode))
    }

    func testHotkeyShortcutPersistsDisplayAndComponents() {
        let shortcut = HotkeyShortcut(
            keyCode: 0,
            modifiers: UInt32(optionKey | controlKey)
        )

        settings.hotkeyShortcut = shortcut

        XCTAssertEqual(settings.hotkeyShortcut, shortcut)
        XCTAssertEqual(settings[.hotkeyKeyCode], 0)
        XCTAssertEqual(settings[.hotkeyModifiers], Int(optionKey | controlKey))
        XCTAssertEqual(settings.hotkeyShortcut.displayString, "⌃⌥ A")
    }

    func testInvalidStoredHotkeyShortcutFallsBackToDefault() {
        settings[.hotkeyKeyCode] = 0
        settings[.hotkeyModifiers] = 0

        XCTAssertEqual(settings.hotkeyShortcut, .defaultShortcut)
    }

    func testModifierOnlyHotkeyShortcutPersistsAndDisplays() {
        let rightOption = HotkeyShortcut(
            keyCode: UInt32(kVK_RightOption),
            modifiers: 0
        )

        settings.hotkeyShortcut = rightOption

        XCTAssertEqual(settings.hotkeyShortcut, rightOption)
        XCTAssertEqual(settings[.hotkeyKeyCode], Int(kVK_RightOption))
        XCTAssertEqual(settings[.hotkeyModifiers], 0)
        XCTAssertTrue(settings.hotkeyShortcut.isModifierOnly)
        XCTAssertEqual(settings.hotkeyShortcut.displayString, "Right Option")
    }

    func testStoredModifierOnlyShortcutDoesNotFallBackToDefault() {
        // keyCode 0 with no modifiers is invalid (plain "A" with no required
        // modifier) and falls back; a real modifier-only key code must not.
        settings[.hotkeyKeyCode] = Int(kVK_RightOption)
        settings[.hotkeyModifiers] = 0

        XCTAssertEqual(
            settings.hotkeyShortcut,
            HotkeyShortcut(keyCode: UInt32(kVK_RightOption), modifiers: 0)
        )
        XCTAssertNotEqual(settings.hotkeyShortcut, .defaultShortcut)
    }

    func testHotkeyActivationModePersists() {
        settings.hotkeyActivationMode = .automatic

        XCTAssertEqual(settings.hotkeyActivationMode, .automatic)
        XCTAssertEqual(settings[.hotkeyActivationMode], HotkeyActivationMode.automatic.rawValue)
    }

    func testPersistenceAcrossAccesses() {
        settings[.vocabularyPrompt] = "persistent test value"

        // Access multiple times
        let value1 = settings[.vocabularyPrompt]
        let value2 = settings[.vocabularyPrompt]
        let value3 = settings[.vocabularyPrompt]

        XCTAssertEqual(value1, value2)
        XCTAssertEqual(value2, value3)
        XCTAssertEqual(value1, "persistent test value")
    }

    func testEmptyStringIsValidValue() {
        settings[.vocabularyPrompt] = ""

        // Empty string should be stored (not confused with default)
        XCTAssertEqual(settings[.vocabularyPrompt], "")
        XCTAssertTrue(settings.isSet(.vocabularyPrompt))
    }

    func testSettingKeysAreCorrect() {
        // Verify that the underlying keys are what we expect
        // This ensures backward compatibility with existing settings
        let modelKey = "selectedModel"
        let languageKey = "selectedLanguage"

        // Set using UserDefaults directly
        userDefaults.set("direct-model", forKey: modelKey)
        userDefaults.set("direct-language", forKey: languageKey)

        // Read using SettingsStore
        XCTAssertEqual(settings[.selectedModel], "direct-model")
        XCTAssertEqual(settings[.selectedLanguage], "direct-language")

        // Cleanup
        userDefaults.removeObject(forKey: modelKey)
        userDefaults.removeObject(forKey: languageKey)
    }

    // MARK: - Replacement entries

    func testReplacementEntriesRoundTripAndRemove() {
        XCTAssertEqual(settings.replacementEntries, [])
        XCTAssertFalse(settings.isSet(.replacementEntries))

        let entries = [
            ReplacementEntry(triggers: ["troy", "señor chang"], replacement: "Troy Barnes")
        ]
        settings.replacementEntries = entries

        XCTAssertEqual(settings.replacementEntries, entries)
        XCTAssertTrue(settings.isSet(.replacementEntries))
        // The underlying storage is a JSON string under the typed setting key.
        XCTAssertTrue(settings[.replacementEntries].contains("Troy Barnes"))

        settings.remove(.replacementEntries)
        XCTAssertEqual(settings.replacementEntries, [])
        XCTAssertEqual(settings[.replacementEntries], "")
        XCTAssertFalse(settings.isSet(.replacementEntries))
    }

    func testReplacementEntriesDecodesCorruptStoredJSONAsEmpty() {
        userDefaults.set("{broken", forKey: AppSettingKey.replacementEntries)

        // Corrupt JSON recovers to an empty list rather than throwing.
        XCTAssertEqual(settings.replacementEntries, [])
    }
}
