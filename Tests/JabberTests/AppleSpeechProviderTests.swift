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

    // MARK: - Bug: transcribe must honor the passed language over the stale

    // preparedLocale. The Speech-API path needs a real device, so this guards
    // the pure locale-resolution decision that drives it.

    func testResolveLocalePrefersPassedLanguageOverPreparedLocale() {
        // User switched English -> German without switching models: the passed
        // language must win over the locale captured at load() time.
        let prepared = Locale(identifier: "en-US")
        XCTAssertEqual(
            AppleSpeechProvider.resolveLocale(language: "de", preparedLocale: prepared),
            Locale(identifier: "de-DE")
        )
    }

    func testResolveLocaleKeepsPreparedLocaleForAutoDetect() {
        // Auto-detect (nil language) must keep the prepared locale instead of
        // drifting to Locale.current mid-session.
        let prepared = Locale(identifier: "es-ES")
        XCTAssertEqual(
            AppleSpeechProvider.resolveLocale(language: nil, preparedLocale: prepared),
            prepared
        )
    }

    func testResolveLocaleFallsBackToCurrentWhenNothingPrepared() {
        XCTAssertEqual(
            AppleSpeechProvider.resolveLocale(language: nil, preparedLocale: nil),
            Locale.current
        )
    }

    func testResolveLocaleUsesCodeDirectlyWhenUnmapped() {
        XCTAssertEqual(
            AppleSpeechProvider.resolveLocale(language: "xx", preparedLocale: Locale(identifier: "en-US")),
            Locale(identifier: "xx")
        )
    }
}
