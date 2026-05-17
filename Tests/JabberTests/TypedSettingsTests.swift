import XCTest
@testable import Jabber
import Foundation

final class TypedSettingsTests: XCTestCase {
    private var settings: SettingsStore!
    private var userDefaultsSuiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaultsSuiteName = "JabberTests.TypedSettings.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName))
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        settings = SettingsStore(userDefaults: userDefaults)
    }
    
    override func tearDownWithError() throws {
        if let userDefaultsSuiteName, let userDefaults {
            userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        }
        settings = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        try super.tearDownWithError()
    }
    
    func testDefaultValues() {
        XCTAssertEqual(settings[.selectedModel], AppMode.baseModelId, "Default model should be base")
        XCTAssertEqual(settings[.selectedLanguage], Constants.defaultLanguage, "Default language should match system")
        XCTAssertEqual(settings[.vocabularyPrompt], "", "Default vocabulary should be empty")
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
        // Set a non-default value
        settings[.selectedModel] = AppMode.largeModelId
        XCTAssertEqual(settings[.selectedModel], AppMode.largeModelId)
        
        // Remove it
        settings.remove(.selectedModel)
        
        // Should return to default
        XCTAssertEqual(settings[.selectedModel], AppMode.baseModelId)
        XCTAssertFalse(settings.isSet(.selectedModel))
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
