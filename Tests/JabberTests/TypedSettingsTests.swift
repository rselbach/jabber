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
    }

    func testLegacyPasteOutputModeMigratesToDirectTyping() {
        userDefaults.set("paste", forKey: AppSettingKey.outputMode)

        XCTAssertEqual(settings[.outputMode], TypingService.OutputMode.directTyping.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.outputMode), TypingService.OutputMode.directTyping.rawValue)
    }

    func testInvalidHotkeyActivationModeMigratesToDefault() {
        userDefaults.set("changnesia", forKey: AppSettingKey.hotkeyActivationMode)

        XCTAssertEqual(settings[.hotkeyActivationMode], HotkeyActivationMode.defaultMode.rawValue)
        XCTAssertEqual(userDefaults.string(forKey: AppSettingKey.hotkeyActivationMode), HotkeyActivationMode.defaultMode.rawValue)
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
        XCTAssertFalse(settings.isSet(.didShowFirstRunSetup))
        XCTAssertFalse(settings.isSet(.onboardingCompleted))
        XCTAssertFalse(settings.isSet(.pauseMediaDuringRecording))
        XCTAssertFalse(settings.isSet(.saveHistoryEnabled))

        settings[.didShowFirstRunSetup] = true
        settings[.onboardingCompleted] = true
        settings[.pauseMediaDuringRecording] = true
        settings[.saveHistoryEnabled] = true

        XCTAssertTrue(settings[.didShowFirstRunSetup])
        XCTAssertTrue(settings[.onboardingCompleted])
        XCTAssertTrue(settings[.pauseMediaDuringRecording])
        XCTAssertTrue(settings[.saveHistoryEnabled])
        XCTAssertTrue(settings.isSet(.didShowFirstRunSetup))
        XCTAssertTrue(settings.isSet(.onboardingCompleted))
        XCTAssertTrue(settings.isSet(.pauseMediaDuringRecording))
        XCTAssertTrue(settings.isSet(.saveHistoryEnabled))
    }

    func testBoolSettingRemoveResetsToDefault() {
        settings[.didShowFirstRunSetup] = true
        settings[.onboardingCompleted] = true
        settings[.pauseMediaDuringRecording] = true
        settings[.saveHistoryEnabled] = true
        XCTAssertTrue(settings[.didShowFirstRunSetup])
        XCTAssertTrue(settings[.onboardingCompleted])
        XCTAssertTrue(settings[.pauseMediaDuringRecording])
        XCTAssertTrue(settings[.saveHistoryEnabled])

        settings.remove(.didShowFirstRunSetup)
        settings.remove(.onboardingCompleted)
        settings.remove(.pauseMediaDuringRecording)
        settings.remove(.saveHistoryEnabled)

        XCTAssertFalse(settings[.didShowFirstRunSetup])
        XCTAssertFalse(settings[.onboardingCompleted])
        XCTAssertFalse(settings[.pauseMediaDuringRecording])
        XCTAssertFalse(settings[.saveHistoryEnabled])
        XCTAssertFalse(settings.isSet(.didShowFirstRunSetup))
        XCTAssertFalse(settings.isSet(.onboardingCompleted))
        XCTAssertFalse(settings.isSet(.pauseMediaDuringRecording))
        XCTAssertFalse(settings.isSet(.saveHistoryEnabled))
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
}
