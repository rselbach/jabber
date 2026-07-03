import XCTest
@testable import Jabber

/// Tests that `RoutedPostProcessor` reads the selected provider at call time
/// from UserDefaults (not at construction) so the coordinator never needs
/// rebuilding on setting changes. These only exercise `displayName`, which
/// reads the provider-kind setting without touching the Keychain or Apple
/// Intelligence availability, keeping them deterministic.
final class RoutedPostProcessorTests: XCTestCase {
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: AppSettingKey.postProcessingProviderKind)
        UserDefaults.standard.removeObject(forKey: AppSettingKey.openRouterModel)
        try await super.tearDown()
    }

    func testDisplayNameDefaultsToAppleIntelligence() {
        UserDefaults.standard.removeObject(forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor().displayName, "Apple Intelligence")
    }

    func testDisplayNameReflectsOpenRouterSelection() {
        UserDefaults.standard.set(PostProcessingProviderKind.openRouter.rawValue, forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor().displayName, "OpenRouter")
    }

    func testDisplayNameReflectsAppleIntelligenceSelection() {
        UserDefaults.standard.set(PostProcessingProviderKind.appleIntelligence.rawValue, forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor().displayName, "Apple Intelligence")
    }

    func testDisplayNameFallsBackForInvalidStoredKind() {
        UserDefaults.standard.set("changnesia", forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor().displayName, "Apple Intelligence")
    }

    func testRouterConformsToPostProcessingProvider() {
        // Compile-time + runtime confirmation that the router satisfies the
        // protocol the coordinator depends on.
        let provider: any PostProcessingProvider = RoutedPostProcessor()
        XCTAssertFalse(provider.displayName.isEmpty)
    }
}
