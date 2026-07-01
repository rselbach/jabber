import XCTest
@testable import Jabber

final class LanguageModelCatalogTests: XCTestCase {
    func testEuropeanLanguageRecommendsParakeet() {
        let route = LanguageModelCatalog.routes(for: "de")
        XCTAssertEqual(route.first?.modelId, AppMode.parakeetModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
    }

    func testEnglishRecommendsNemotron() {
        let route = LanguageModelCatalog.routes(for: "en")
        XCTAssertEqual(route.first?.modelId, AppMode.nemotronModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
    }

    func testEnglishRouteIncludesParakeetButNotAsRecommended() {
        let route = LanguageModelCatalog.routes(for: "en")
        XCTAssertTrue(route.contains { $0.modelId == AppMode.parakeetModelId })
        XCTAssertFalse(route.first { $0.modelId == AppMode.parakeetModelId }?.isRecommended == true)
    }

    func testNonEuropeanLanguageRecommendsQwen3() {
        let route = LanguageModelCatalog.routes(for: "ja")
        XCTAssertEqual(route.first?.modelId, AppMode.qwen3ModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
    }

    func testAutoDetectRecommendsParakeet() {
        let route = LanguageModelCatalog.routes(for: "auto")
        XCTAssertEqual(route.first?.modelId, AppMode.parakeetModelId)
    }

    func testEuropeanLanguageIncludesParakeet() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "fr")
        XCTAssertTrue(ids.contains(AppMode.parakeetModelId))
        XCTAssertTrue(ids.contains(AppMode.qwen3ModelId))
    }

    func testEnglishIncludesNemotron() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "en")
        XCTAssertTrue(ids.contains(AppMode.nemotronModelId))
        XCTAssertTrue(ids.contains(AppMode.parakeetModelId))
        XCTAssertTrue(ids.contains(AppMode.qwen3ModelId))
    }

    func testNonEuropeanLanguageExcludesParakeet() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "zh")
        XCTAssertFalse(ids.contains(AppMode.parakeetModelId))
        XCTAssertTrue(ids.contains(AppMode.qwen3ModelId))
    }

    func testNonEuropeanLanguageOnlyHasQwen3() {
        let ids = LanguageModelCatalog.compatibleModelIds(for: "zh")
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids.first, AppMode.qwen3ModelId)
    }

    func testSupportsLanguageReturnsTrueForMatchingModel() {
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("de", modelId: AppMode.parakeetModelId))
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("ja", modelId: AppMode.qwen3ModelId))
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("en", modelId: AppMode.nemotronModelId))
    }

    func testSupportsLanguageReturnsFalseForNonMatchingModel() {
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("ja", modelId: AppMode.parakeetModelId))
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("th", modelId: AppMode.parakeetModelId))
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("de", modelId: AppMode.nemotronModelId))
        XCTAssertFalse(LanguageModelCatalog.supportsLanguage("ja", modelId: AppMode.nemotronModelId))
    }

    func testQwen3SupportsAllLanguages() {
        for code in Constants.validLanguageCodes {
            XCTAssertTrue(LanguageModelCatalog.supportsLanguage(code, modelId: AppMode.qwen3ModelId),
                         "Qwen3 should support language '\(code)'")
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

    func testRecommendedModelIdForAutoReturnsParakeet() {
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "auto"),
            AppMode.parakeetModelId
        )
    }

    func testRecommendedModelIdForUnknownLanguageReturnsQwen3() {
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "xx"),
            AppMode.qwen3ModelId
        )
    }

    func testAllParakeetLanguagesAreSupported() {
        for code in AppMode.parakeetLanguageCodes {
            let routes = LanguageModelCatalog.routes(for: code)
            XCTAssertTrue(routes.contains { $0.modelId == AppMode.parakeetModelId },
                         "Parakeet should be in routes for language '\(code)'")
        }
    }

    func testNemotronOnlySupportsEnglish() {
        XCTAssertTrue(LanguageModelCatalog.supportsLanguage("en", modelId: AppMode.nemotronModelId))
        for code in AppMode.parakeetLanguageCodes where code != "en" {
            XCTAssertFalse(LanguageModelCatalog.supportsLanguage(code, modelId: AppMode.nemotronModelId),
                         "Nemotron should not support language '\(code)'")
        }
    }
}
