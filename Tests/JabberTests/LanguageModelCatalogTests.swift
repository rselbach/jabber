import XCTest
@testable import Jabber

final class LanguageModelCatalogTests: XCTestCase {
    func testNonEnglishLanguageRecommendsQwen3() {
        let route = LanguageModelCatalog.routes(for: "de")
        XCTAssertEqual(route.first?.modelId, AppMode.qwen3ModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
    }

    func testEnglishRecommendsNemotron() {
        let route = LanguageModelCatalog.routes(for: "en")
        XCTAssertEqual(route.first?.modelId, AppMode.nemotronModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
    }

    func testEnglishIncludesAllQwen3ModelsButDoesNotRecommendThem() {
        let route = LanguageModelCatalog.routes(for: "en")
        assertIncludesAllQwen3Models(route.map(\.modelId))
        for modelId in AppMode.qwen3ModelIds {
            XCTAssertFalse(route.first { $0.modelId == modelId }?.isRecommended == true)
        }
    }

    func testNonEuropeanLanguageRecommendsQwen3() {
        let route = LanguageModelCatalog.routes(for: "ja")
        XCTAssertEqual(route.first?.modelId, AppMode.qwen3ModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
    }

    func testAutoDetectRecommendsQwen3AndKeepsNemotronAsOption() {
        let route = LanguageModelCatalog.routes(for: "auto")
        let recommended = route.first { $0.isRecommended }
        XCTAssertEqual(recommended?.modelId, AppMode.qwen3ModelId)

        let nemotron = route.first { $0.modelId == AppMode.nemotronModelId }
        XCTAssertNotNil(nemotron, "Nemotron should remain selectable for auto")
        XCTAssertFalse(nemotron?.isRecommended == true, "Nemotron should not be recommended for auto")
    }

    func testEuropeanLanguageIncludesQwen3Models() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "fr")
        assertIncludesAllQwen3Models(ids)
    }

    func testEnglishIncludesNemotron() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "en")
        XCTAssertTrue(ids.contains(AppMode.nemotronModelId))
        assertIncludesAllQwen3Models(ids)
    }

    func testNonEuropeanLanguageExcludesNemotron() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "zh")
        XCTAssertFalse(ids.contains(AppMode.nemotronModelId))
        assertIncludesAllQwen3Models(ids)
    }

    func testNonEuropeanLanguageOnlyHasQwen3ModelsAndAppleSpeech() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "zh")
        assertIncludesAllQwen3Models(ids)
        XCTAssertTrue(ids.contains(AppMode.appleSpeechModelId))
        XCTAssertFalse(ids.contains(AppMode.nemotronModelId))
    }

    func testAppleSpeechIsNeverRecommended() {
        for code in ["auto", "en", "de", "ja", "zh"] {
            let routes = LanguageModelCatalog.routes(for: code)
            let appleRoute = routes.first { $0.modelId == AppMode.appleSpeechModelId }
            XCTAssertNotNil(appleRoute, "Apple Speech should appear for language '\(code)'")
            XCTAssertFalse(appleRoute?.isRecommended == true, "Apple Speech should never be recommended")
        }
    }

    func testSupportsLanguageReturnsTrueForMatchingModel() {
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("ja", modelId: AppMode.qwen3ModelId))
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("en", modelId: AppMode.nemotronModelId))
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("zh", modelId: AppMode.appleSpeechModelId))
    }

    func testSupportsLanguageReturnsFalseForNonMatchingModel() {
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("de", modelId: AppMode.nemotronModelId))
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("ja", modelId: AppMode.nemotronModelId))
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("en", modelId: "parakeet"))
    }

    func testQwen3SupportsAllLanguages() {
        for modelId in AppMode.qwen3ModelIds {
            for code in Constants.validLanguageCodes {
                XCTAssertTrue(LanguageModelCatalog.supportsLanguage(code, modelId: modelId),
                              "\(modelId) should support language '\(code)'")
            }
        }
    }

    func testPopularLanguagesAreNonEmpty() {
        XCTAssertFalse(LanguageModelCatalog.popularLanguages().isEmpty)
    }

    func testAllLanguagesIncludePopularOnes() {
        let popular = LanguageModelCatalog.popularLanguages()
        let all = LanguageModelCatalog.allLanguages()
        for p in popular {
            XCTAssertTrue(all.contains { $0.code == p.code }, "Popular language '\(p.code)' should be in allLanguages")
        }
    }

    func testRecommendedModelIdForAutoReturnsQwen3() {
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "auto"),
            AppMode.qwen3ModelId
        )
    }

    func testRecommendedModelIdForEnglishStillReturnsNemotron() {
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "en"),
            AppMode.nemotronModelId
        )
    }

    func testRecommendedModelIdForUnknownLanguageReturnsQwen3() {
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "xx"),
            AppMode.qwen3ModelId
        )
    }

    func testNemotronOnlySupportsEnglish() {
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("en", modelId: AppMode.nemotronModelId))
        for code in Constants.validLanguageCodes where code != "en" {
            XCTAssertFalse(LanguageModelCatalog.supportsLanguage(code, modelId: AppMode.nemotronModelId),
                           "Nemotron should not support language '\(code)'")
        }
    }

    func testParakeetIsNotASelectableModel() {
        XCTAssertFalse(AppMode.modelDefinitions.contains { $0.id == "parakeet" })
    }

    private func assertIncludesAllQwen3Models(_ ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        for modelId in AppMode.qwen3ModelIds {
            XCTAssertTrue(ids.contains(modelId), "Missing \(modelId)", file: file, line: line)
        }
    }
}
