import XCTest
@testable import Jabber

final class AppleSpeechProviderTests: XCTestCase {
    func testLocaleMapCoversAllValidLanguageCodes() {
        for code in Constants.validLanguageCodes {
            XCTAssertNotNil(
                AppleSpeechProvider.localeMap[code],
                "Language code '\(code)' has no locale mapping in AppleSpeechProvider.localeMap"
            )
        }
    }

    func testLocaleForKnownCodeReturnsMappedIdentifier() {
        XCTAssertEqual(AppleSpeechProvider.locale(for: "en").identifier, AppleSpeechProvider.localeMap["en"])
        XCTAssertEqual(AppleSpeechProvider.locale(for: "es").identifier, AppleSpeechProvider.localeMap["es"])
        XCTAssertEqual(AppleSpeechProvider.locale(for: "zh").identifier, AppleSpeechProvider.localeMap["zh"])
        XCTAssertEqual(AppleSpeechProvider.locale(for: "pt").identifier, AppleSpeechProvider.localeMap["pt"])
    }

    func testLocaleForNilReturnsCurrentLocale() {
        XCTAssertEqual(AppleSpeechProvider.locale(for: nil), Locale.current)
    }

    func testLocaleForAutoReturnsCurrentLocale() {
        XCTAssertEqual(AppleSpeechProvider.locale(for: "auto"), Locale.current)
    }

    func testLocaleForUnknownCodeUsesCodeDirectly() {
        let result = AppleSpeechProvider.locale(for: "xx")
        XCTAssertEqual(result.identifier, "xx")
    }

    func testNormalizedProducesBCP47WithHyphens() {
        let locale = Locale(identifier: "en_US")
        let normalized = AppleSpeechProvider.normalized(locale)
        XCTAssertTrue(normalized.contains("-"), "normalized locale should use hyphens, got: \(normalized)")
        XCTAssertFalse(normalized.contains("_"), "normalized locale should not use underscores, got: \(normalized)")
    }

    func testNormalizedHasNoUnderscoresForAllMappedLocales() {
        for (code, _) in AppleSpeechProvider.localeMap {
            let locale = AppleSpeechProvider.locale(for: code)
            let normalized = AppleSpeechProvider.normalized(locale)
            XCTAssertFalse(
                normalized.contains("_"),
                "normalized('\(code)') = '\(normalized)' should not contain underscores"
            )
        }
    }
}
