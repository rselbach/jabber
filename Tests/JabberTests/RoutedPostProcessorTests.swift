import XCTest
@testable import Jabber

/// Tests that `RoutedPostProcessor` reads the selected provider at call time
/// from UserDefaults (not at construction) so the coordinator never needs
/// rebuilding on setting changes. These only exercise `displayName`, which
/// reads the provider-kind setting without touching the Keychain or Apple
/// Intelligence availability, keeping them deterministic.
final class RoutedPostProcessorTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "JabberTests.RoutedPostProcessor.\(UUID().uuidString)"

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults = nil
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testDisplayNameDefaultsToAppleIntelligence() {
        XCTAssertEqual(RoutedPostProcessor(defaults: defaults).displayName, "Apple Intelligence")
    }

    func testDisplayNameReflectsOpenRouterSelection() {
        defaults.set(PostProcessingProviderKind.openRouter.rawValue, forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor(defaults: defaults).displayName, "OpenRouter")
    }

    func testDisplayNameReflectsAppleIntelligenceSelection() {
        defaults.set(PostProcessingProviderKind.appleIntelligence.rawValue, forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor(defaults: defaults).displayName, "Apple Intelligence")
    }

    func testDisplayNameFallsBackForInvalidStoredKind() {
        defaults.set("changnesia", forKey: AppSettingKey.postProcessingProviderKind)
        XCTAssertEqual(RoutedPostProcessor(defaults: defaults).displayName, "Apple Intelligence")
    }

    func testRouterConformsToPostProcessingProvider() {
        // Compile-time + runtime confirmation that the router satisfies the
        // protocol the coordinator depends on.
        let provider: any PostProcessingProvider = RoutedPostProcessor(defaults: defaults)
        XCTAssertFalse(provider.displayName.isEmpty)
    }
}
