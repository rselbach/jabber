import XCTest
@testable import Jabber

final class OpenRouterModelCatalogTests: XCTestCase {
    func testHasExactlyThreeCuratedModels() {
        XCTAssertEqual(OpenRouterModelCatalog.models.count, 3)
    }

    func testModelIdsAreUnique() {
        let ids = OpenRouterModelCatalog.models.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Model slugs must be unique.")
    }

    func testDisplayNamesAreUnique() {
        let names = OpenRouterModelCatalog.models.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "Display names must be unique.")
    }

    func testDefaultModelIdIsInCatalog() {
        XCTAssertTrue(OpenRouterModelCatalog.model(forId: OpenRouterModelCatalog.defaultModelId) != nil)
    }

    func testDefaultModelMatchesDefaultId() {
        XCTAssertEqual(OpenRouterModelCatalog.defaultModel.id, OpenRouterModelCatalog.defaultModelId)
    }

    func testCuratedSlugsAndDisplayNames() {
        let byId = Dictionary(uniqueKeysWithValues: OpenRouterModelCatalog.models.map { ($0.id, $0.displayName) })
        XCTAssertEqual(byId["~openai/gpt-mini-latest"], "GPT Mini (latest)")
        XCTAssertEqual(byId["~anthropic/claude-haiku-latest"], "Claude Haiku (latest)")
        XCTAssertEqual(byId["google/gemini-3.1-flash-lite"], "Gemini Flash Lite")
    }

    func testModelForUnknownIdReturnsNil() {
        XCTAssertNil(OpenRouterModelCatalog.model(forId: "openai/gpt-4o"))
    }

    func testResolveModelIdFallsBackToDefaultForNil() {
        XCTAssertEqual(OpenRouterModelCatalog.resolveModelId(nil), OpenRouterModelCatalog.defaultModelId)
    }

    func testResolveModelIdFallsBackToDefaultForUnknownSlug() {
        XCTAssertEqual(
            OpenRouterModelCatalog.resolveModelId("openai/gpt-4o"),
            OpenRouterModelCatalog.defaultModelId
        )
    }

    func testResolveModelIdReturnsKnownSlugVerbatim() {
        let slug = "~anthropic/claude-haiku-latest"
        XCTAssertEqual(OpenRouterModelCatalog.resolveModelId(slug), slug)
    }
}

final class OpenCodeZenModelCatalogTests: XCTestCase {
    func testHasThreeCuratedChatCompletionsModels() {
        XCTAssertEqual(OpenCodeZenModelCatalog.models.count, 3)
    }

    func testModelsAreUniqueAndDefaultIsPresent() {
        let ids = OpenCodeZenModelCatalog.models.map(\.id)
        let names = OpenCodeZenModelCatalog.models.map(\.displayName)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(OpenCodeZenModelCatalog.defaultModel.id, OpenCodeZenModelCatalog.defaultModelId)
    }

    func testCuratedModels() {
        let byId = Dictionary(uniqueKeysWithValues: OpenCodeZenModelCatalog.models.map { ($0.id, $0.displayName) })
        XCTAssertEqual(byId["deepseek-v4-flash"], "DeepSeek V4 Flash")
        XCTAssertEqual(byId["minimax-m3"], "MiniMax M3")
        XCTAssertEqual(byId["glm-5.2"], "GLM 5.2")
    }

    func testResolution() {
        XCTAssertEqual(OpenCodeZenModelCatalog.resolveModelId(nil), OpenCodeZenModelCatalog.defaultModelId)
        XCTAssertEqual(OpenCodeZenModelCatalog.resolveModelId("gpt-5.4-mini"), OpenCodeZenModelCatalog.defaultModelId)
        XCTAssertEqual(OpenCodeZenModelCatalog.resolveModelId("minimax-m3"), "minimax-m3")
    }
}

final class PostProcessingProviderKindTests: XCTestCase {
    func testAllCasesContainAllProviders() {
        XCTAssertEqual(Set(PostProcessingProviderKind.allCases), [.appleIntelligence, .openRouter, .openCodeZen])
    }

    func testDefaultIsAppleIntelligence() {
        XCTAssertEqual(PostProcessingProviderKind.defaultValue, .appleIntelligence)
    }

    func testDisplayNames() {
        XCTAssertEqual(PostProcessingProviderKind.appleIntelligence.displayName, "Apple Intelligence")
        XCTAssertEqual(PostProcessingProviderKind.openRouter.displayName, "OpenRouter")
        XCTAssertEqual(PostProcessingProviderKind.openCodeZen.displayName, "OpenCode Zen")
    }

    func testResolveNilReturnsDefault() {
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: nil), .defaultValue)
    }

    func testResolveInvalidReturnsDefault() {
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "greendale"), .defaultValue)
    }

    func testResolveValidReturnsIt() {
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "openRouter"), .openRouter)
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "openCodeZen"), .openCodeZen)
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "appleIntelligence"), .appleIntelligence)
    }

    func testRawValuesRoundTrip() {
        for kind in PostProcessingProviderKind.allCases {
            XCTAssertEqual(PostProcessingProviderKind(rawValue: kind.rawValue), kind)
        }
    }
}
