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
        // Chinese has no local model; v3 is European-only and the Japanese
        // model is monolingual.
        XCTAssertEqual(
            LanguageModelCatalog.compatibleModelIds(for: "zh"),
            [AppMode.appleSpeechModelId]
        )
        XCTAssertEqual(
            LanguageModelCatalog.recommendedModelId(for: "zh"),
            AppMode.appleSpeechModelId
        )
    }

    func testJapaneseRecommendsTheJapaneseParakeet() {
        let route = LanguageModelCatalog.routes(for: "ja")

        XCTAssertEqual(route.first?.modelId, AppMode.parakeetJapaneseModelId)
        XCTAssertTrue(route.first?.isRecommended == true)
        XCTAssertTrue(route.contains { $0.modelId == AppMode.appleSpeechModelId })
        XCTAssertFalse(
            LanguageModelCatalog.supportsLanguage("en", modelId: AppMode.parakeetJapaneseModelId)
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

    func testCompatibilityDescribesWhatTheModelWillDo() {
        let cases: [String: (language: String, modelId: String, systemLanguage: String?, want: LanguageModelCompatibility?)] = [
            "english on parakeet v2 is supported": (
                "en", AppMode.parakeetModelId, "pt", .supported
            ),
            "english on parakeet v3 is supported": (
                "en", AppMode.parakeetMultilingualModelId, "pt", .supported
            ),
            "english on nemotron is supported": (
                "en", AppMode.nemotronModelId, "pt", .supported
            ),
            "english on apple speech is supported": (
                "en", AppMode.appleSpeechModelId, "pt", .supported
            ),
            "english on parakeet japanese recommends parakeet v2": (
                "en", AppMode.parakeetJapaneseModelId, "pt",
                .unsupported(recommendedModelId: AppMode.parakeetModelId)
            ),
            "german on parakeet v2 recommends parakeet v3": (
                "de", AppMode.parakeetModelId, "pt",
                .unsupported(recommendedModelId: AppMode.parakeetMultilingualModelId)
            ),
            "german on nemotron recommends parakeet v3": (
                "de", AppMode.nemotronModelId, "pt",
                .unsupported(recommendedModelId: AppMode.parakeetMultilingualModelId)
            ),
            "german on parakeet japanese recommends parakeet v3": (
                "de", AppMode.parakeetJapaneseModelId, "pt",
                .unsupported(recommendedModelId: AppMode.parakeetMultilingualModelId)
            ),
            "german on parakeet v3 is supported": (
                "de", AppMode.parakeetMultilingualModelId, "pt", .supported
            ),
            "german on apple speech is supported": (
                "de", AppMode.appleSpeechModelId, "pt", .supported
            ),
            "japanese on parakeet v2 recommends parakeet japanese": (
                "ja", AppMode.parakeetModelId, "pt",
                .unsupported(recommendedModelId: AppMode.parakeetJapaneseModelId)
            ),
            "japanese on parakeet v3 recommends parakeet japanese": (
                "ja", AppMode.parakeetMultilingualModelId, "pt",
                .unsupported(recommendedModelId: AppMode.parakeetJapaneseModelId)
            ),
            "japanese on parakeet japanese is supported": (
                "ja", AppMode.parakeetJapaneseModelId, "pt", .supported
            ),
            "korean on parakeet v2 recommends apple speech": (
                "ko", AppMode.parakeetModelId, "pt",
                .unsupported(recommendedModelId: AppMode.appleSpeechModelId)
            ),
            "korean on parakeet v3 recommends apple speech": (
                "ko", AppMode.parakeetMultilingualModelId, "pt",
                .unsupported(recommendedModelId: AppMode.appleSpeechModelId)
            ),
            "korean on parakeet japanese recommends apple speech": (
                "ko", AppMode.parakeetJapaneseModelId, "pt",
                .unsupported(recommendedModelId: AppMode.appleSpeechModelId)
            ),
            "korean on apple speech is supported": (
                "ko", AppMode.appleSpeechModelId, "pt", .supported
            ),
            "auto on parakeet v3 detects the language": (
                "auto", AppMode.parakeetMultilingualModelId, "pt", .detectsLanguage
            ),
            "auto on parakeet v2 assumes english": (
                "auto", AppMode.parakeetModelId, "pt", .assumesLanguage("en")
            ),
            "auto on nemotron assumes english": (
                "auto", AppMode.nemotronModelId, "pt", .assumesLanguage("en")
            ),
            "auto on parakeet japanese assumes japanese": (
                "auto", AppMode.parakeetJapaneseModelId, "pt", .assumesLanguage("ja")
            ),
            "auto on apple speech uses the system language": (
                "auto", AppMode.appleSpeechModelId, "pt", .usesSystemLanguage("pt")
            ),
            "auto on apple speech without a system language": (
                "auto", AppMode.appleSpeechModelId, nil, .usesSystemLanguage(nil)
            ),
            "auto on parakeet v2 ignores the system language": (
                "auto", AppMode.parakeetModelId, "de", .assumesLanguage("en")
            ),
            "unknown model has no answer": (
                "en", "changnesia", "pt", nil
            )
        ]

        for (name, tc) in cases {
            let got = LanguageModelCatalog.compatibility(
                languageCode: tc.language,
                modelId: tc.modelId,
                systemLanguageCode: tc.systemLanguage
            )
            XCTAssertEqual(got, tc.want, name)
        }
    }

    func testCompatibilityRecommendsAWorkingModelForEveryCombination() {
        // Guards the Speech page warning: its fix button must never offer the
        // model that is already selected, nor one that also gets it wrong.
        let languages = Constants.validLanguageCodes.union(["auto"])

        for model in AppMode.modelDefinitions {
            for language in languages {
                let name = "\(language) on \(model.id)"
                let got = LanguageModelCatalog.compatibility(
                    languageCode: language,
                    modelId: model.id,
                    systemLanguageCode: "en"
                )

                switch got {
                case .unsupported(let recommendedModelId):
                    XCTAssertNotEqual(recommendedModelId, model.id, name)
                    XCTAssertTrue(
                        LanguageModelCatalog.supportsLanguage(language, modelId: recommendedModelId),
                        name
                    )
                case .assumesLanguage(let code):
                    XCTAssertTrue(Constants.validLanguageCodes.contains(code), name)
                case .supported, .detectsLanguage, .usesSystemLanguage:
                    break
                case .none:
                    XCTFail("no compatibility for \(name)")
                }
            }
        }
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
