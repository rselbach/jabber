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

    func testNonEnglishLanguageOnlyOffersAppleSpeech() {
        XCTAssertEqual(
            LanguageModelCatalog.compatibleModelIds(for: "ja"),
            [AppMode.appleSpeechModelId]
        )
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "ja"),
            AppMode.appleSpeechModelId
        )
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
