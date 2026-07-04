import XCTest
@testable import Jabber

final class TranscriptionServiceTests: XCTestCase {
    // MARK: - resolveLanguage

    func testResolveLanguageAcceptsAuto() {
        XCTAssertEqual(TranscriptionService.resolveLanguage("auto"), "auto")
    }

    func testResolveLanguageAcceptsValidCode() {
        XCTAssertEqual(TranscriptionService.resolveLanguage("en"), "en")
        XCTAssertEqual(TranscriptionService.resolveLanguage("zh"), "zh")
        XCTAssertEqual(TranscriptionService.resolveLanguage("fa"), "fa")
    }

    func testResolveLanguageFallsBackForInvalidCode() {
        XCTAssertEqual(TranscriptionService.resolveLanguage("xyz"), "auto")
        XCTAssertEqual(TranscriptionService.resolveLanguage(""), "auto")
        XCTAssertEqual(TranscriptionService.resolveLanguage("EN"), "auto")
    }

    func testResolveLanguageAcceptsAllValidLanguageCodes() {
        for code in Constants.validLanguageCodes {
            XCTAssertEqual(
                TranscriptionService.resolveLanguage(code),
                code,
                "resolveLanguage should accept valid code '\(code)'"
            )
        }
    }

    // MARK: - resolveLanguageForProvider

    func testResolveLanguageForProviderReturnsNilForAuto() {
        XCTAssertNil(TranscriptionService.resolveLanguageForProvider("auto"))
    }

    func testResolveLanguageForProviderReturnsCodeForSpecificLanguage() {
        XCTAssertEqual(TranscriptionService.resolveLanguageForProvider("en"), "en")
        XCTAssertEqual(TranscriptionService.resolveLanguageForProvider("ja"), "ja")
    }

    // MARK: - truncateVocabularyPrompt

    func testTruncateVocabularyPromptShortStringUnchanged() {
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt("hello"), "hello")
    }

    func testTruncateVocabularyPromptEmptyStringUnchanged() {
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(""), "")
    }

    func testTruncateVocabularyPromptTruncatesAt500Characters() {
        let short = String(repeating: "a", count: 400)
        let exact = String(repeating: "b", count: 500)
        let long = String(repeating: "c", count: 600)

        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(short).count, 400)
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(exact).count, 500)
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(long).count, 500)
    }
}
