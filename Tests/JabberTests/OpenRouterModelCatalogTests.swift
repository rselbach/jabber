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

final class PostProcessingProviderKindTests: XCTestCase {
    func testAllCasesContainBothProviders() {
        XCTAssertEqual(Set(PostProcessingProviderKind.allCases), [.appleIntelligence, .openRouter])
    }

    func testDefaultIsAppleIntelligence() {
        XCTAssertEqual(PostProcessingProviderKind.defaultValue, .appleIntelligence)
    }

    func testDisplayNames() {
        XCTAssertEqual(PostProcessingProviderKind.appleIntelligence.displayName, "Apple Intelligence")
        XCTAssertEqual(PostProcessingProviderKind.openRouter.displayName, "OpenRouter")
    }

    func testResolveNilReturnsDefault() {
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: nil), .defaultValue)
    }

    func testResolveInvalidReturnsDefault() {
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "greendale"), .defaultValue)
    }

    func testResolveValidReturnsIt() {
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "openRouter"), .openRouter)
        XCTAssertEqual(PostProcessingProviderKind.resolve(rawValue: "appleIntelligence"), .appleIntelligence)
    }

    func testRawValuesRoundTrip() {
        for kind in PostProcessingProviderKind.allCases {
            XCTAssertEqual(PostProcessingProviderKind(rawValue: kind.rawValue), kind)
        }
    }
}
