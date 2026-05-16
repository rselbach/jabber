import XCTest
@testable import Jabber
import Foundation

final class TypedSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up test settings before each test
        TypedSettings.remove(.selectedModel)
        TypedSettings.remove(.selectedLanguage)
        TypedSettings.remove(.vocabularyPrompt)
    }
    
    override func tearDown() {
        // Clean up after each test
        TypedSettings.remove(.selectedModel)
        TypedSettings.remove(.selectedLanguage)
        TypedSettings.remove(.vocabularyPrompt)
        super.tearDown()
    }
    
    func testDefaultValues() {
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.baseModelId, "Default model should be base")
        XCTAssertEqual(TypedSettings[.selectedLanguage], Constants.defaultLanguage, "Default language should match system")
        XCTAssertEqual(TypedSettings[.vocabularyPrompt], "", "Default vocabulary should be empty")
    }
    
    func testSettingAndGettingValues() {
        // Set custom values
        TypedSettings[.selectedModel] = "medium"
        TypedSettings[.selectedLanguage] = "en"
        TypedSettings[.vocabularyPrompt] = "medical terminology"
        
        // Verify they're stored
        XCTAssertEqual(TypedSettings[.selectedModel], "medium")
        XCTAssertEqual(TypedSettings[.selectedLanguage], "en")
        XCTAssertEqual(TypedSettings[.vocabularyPrompt], "medical terminology")
    }
    
    func testIsSetReturnsFalseForUnsetValues() {
        // Ensure settings are not set
        TypedSettings.remove(.selectedModel)
        
        // isSet should return false for unset values
        XCTAssertFalse(TypedSettings.isSet(.selectedModel), "isSet should return false for removed setting")
    }
    
    func testIsSetReturnsTrueForSetValues() {
        TypedSettings[.selectedModel] = "large"
        
        XCTAssertTrue(TypedSettings.isSet(.selectedModel), "isSet should return true for explicitly set value")
    }
    
    func testRemoveResetsToDefault() {
        // Set a non-default value
        TypedSettings[.selectedModel] = AppMode.largeModelId
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.largeModelId)
        
        // Remove it
        TypedSettings.remove(.selectedModel)
        
        // Should return to default
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.baseModelId)
        XCTAssertFalse(TypedSettings.isSet(.selectedModel))
    }
    
    func testPersistenceAcrossAccesses() {
        TypedSettings[.vocabularyPrompt] = "persistent test value"
        
        // Access multiple times
        let value1 = TypedSettings[.vocabularyPrompt]
        let value2 = TypedSettings[.vocabularyPrompt]
        let value3 = TypedSettings[.vocabularyPrompt]
        
        XCTAssertEqual(value1, value2)
        XCTAssertEqual(value2, value3)
        XCTAssertEqual(value1, "persistent test value")
    }
    
    func testEmptyStringIsValidValue() {
        TypedSettings[.vocabularyPrompt] = ""
        
        // Empty string should be stored (not confused with default)
        XCTAssertEqual(TypedSettings[.vocabularyPrompt], "")
        XCTAssertTrue(TypedSettings.isSet(.vocabularyPrompt))
    }
    
    func testSettingKeysAreCorrect() {
        // Verify that the underlying keys are what we expect
        // This ensures backward compatibility with existing settings
        let modelKey = "selectedModel"
        let languageKey = "selectedLanguage"
        
        // Set using UserDefaults directly
        UserDefaults.standard.set("direct-model", forKey: modelKey)
        UserDefaults.standard.set("direct-language", forKey: languageKey)
        
        // Read using TypedSettings
        XCTAssertEqual(TypedSettings[.selectedModel], "direct-model")
        XCTAssertEqual(TypedSettings[.selectedLanguage], "direct-language")
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: modelKey)
        UserDefaults.standard.removeObject(forKey: languageKey)
    }
}
