import XCTest
@testable import Jabber

final class LanguageModelCatalogTests: XCTestCase {
    func testEnglishRecommendsParakeet() {
        let route = LanguageModelCatalog.routes(for: "en")

        XCTAssertEqual(route.first?.modelId, AppMode.parakeetModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
        XCTAssertTrue(route.contains { $0.modelId == AppMode.nemotronModelId })
        XCTAssertTrue(route.contains { $0.modelId == AppMode.appleSpeechModelId })
    }

    func testAutoDetectRecommendsAppleSpeech() {
        let route = LanguageModelCatalog.routes(for: "auto")

        XCTAssertEqual(route.first?.modelId, AppMode.appleSpeechModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
        XCTAssertTrue(route.contains { $0.modelId == AppMode.parakeetModelId })
        XCTAssertTrue(route.contains { $0.modelId == AppMode.nemotronModelId })
    }

    func testLanguageOutsideEveryLocalModelOnlyOffersAppleSpeech() {
        // Japanese is beyond Parakeet v3's 25 European languages.
        XCTAssertEqual(
            LanguageModelCatalog.compatibleModelIds(for: "ja"),
            [AppMode.appleSpeechModelId]
        )
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "ja"),
            AppMode.appleSpeechModelId
        )
    }

    func testEuropeanLanguagesRecommendMultilingualParakeet() {
        let cases: [String: String] = [
            "german uses latin script": "de",
            "portuguese uses latin script": "pt",
            "russian uses cyrillic script": "ru",
            "greek uses its own script": "el"
        ]

        for (name, code) in cases {
            let route = LanguageModelCatalog.routes(for: code)

            XCTAssertEqual(route.first?.modelId, AppMode.parakeetMultilingualModelId, name)
            XCTAssertTrue(route.first?.isRecommended == true, name)
            XCTAssertEqual(
                LanguageModelCatalog.recommendedModelId(for: code),
                AppMode.parakeetMultilingualModelId,
                name
            )
            XCTAssertTrue(route.contains { $0.modelId == AppMode.appleSpeechModelId }, name)
        }
    }

    func testEveryOfferedLanguageParakeetKnowsRoutesToParakeet() {
        // Guards the pairing: a language added to Constants that v3 handles
        // should never be left recommending Apple Speech.
        let routed = Constants.validLanguageCodes
            .filter { $0 != "en" && AppMode.parakeetMultilingualLanguageCodes.contains($0) }

        for code in routed {
            XCTAssertEqual(
                LanguageModelCatalog.recommendedModelId(for: code),
                AppMode.parakeetMultilingualModelId,
                code
            )
        }
    }

    func testEnglishStillPrefersTheEnglishOnlyModel() {
        // v3 is offered for English but v2 scores better on it.
        let route = LanguageModelCatalog.routes(for: "en")

        XCTAssertEqual(route.first?.modelId, AppMode.parakeetModelId)
        XCTAssertTrue(route.contains { $0.modelId == AppMode.parakeetMultilingualModelId })
    }

    func testMultilingualParakeetAcceptsItsLanguagesAndRejectsOthers() {
        for code in ["en", "de", "ru", "el", "pl"] {
            XCTAssertTrue(
                LanguageModelCatalog.supportsLanguage(code, modelId: AppMode.parakeetMultilingualModelId),
                code
            )
        }

        for code in ["ja", "zh", "ar", "hi"] {
            XCTAssertFalse(
                LanguageModelCatalog.supportsLanguage(code, modelId: AppMode.parakeetMultilingualModelId),
                code
            )
        }
    }

    func testUnknownLanguageFallsBackToAppleSpeech() {
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "xx"),
            AppMode.appleSpeechModelId
        )
    }

    func testEnglishOnlyModelsRejectNonEnglishLanguages() {
        for modelId in [AppMode.parakeetModelId, AppMode.nemotronModelId] {
            XCTAssertTrue(LanguageModelCatalog.supportsLanguage("en", modelId: modelId))
            XCTAssertFalse(LanguageModelCatalog.supportsLanguage("de", modelId: modelId))
        }
    }

    func testAppleSpeechSupportsAllLanguages() {
        for code in Constants.validLanguageCodes {
            XCTAssertTrue(LanguageModelCatalog.supportsLanguage(code, modelId: AppMode.appleSpeechModelId))
        }
    }

    func testAutoDetectIsAllowedForEveryModel() {
        for model in AppMode.modelDefinitions {
            XCTAssertTrue(LanguageModelCatalog.supportsLanguage("auto", modelId: model.id))
        }
    }

    func testUnknownModelSupportsNoLanguages() {
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("en", modelId: "changnesia"))
    }

    func testPopularLanguagesAreIncludedInAllLanguages() {
        let popular = LanguageModelCatalog.popularLanguages()
        let all = LanguageModelCatalog.allLanguages()

        XCTAssertFalse(popular.isEmpty)
        for language in popular {
            XCTAssertTrue(all.contains { $0.code == language.code })
        }
    }
}
