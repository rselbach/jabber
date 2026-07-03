import XCTest
@testable import Jabber

/// Navigation-only smoke tests for the onboarding flow. These deliberately
/// stay on the welcome/language boundary: moving forward past the language
/// step kicks off a real model download, and selection APIs write to the
/// shared TypedSettings store.
@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    private var coordinator: OnboardingCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        coordinator = OnboardingCoordinator()
    }

    override func tearDown() async throws {
        coordinator.stop()
        coordinator = nil
        try await super.tearDown()
    }

    func testStepOrder() {
        let want: [OnboardingCoordinator.Step] = [.welcome, .language, .permissions, .modelDownload, .ready]
        XCTAssertEqual(OnboardingCoordinator.Step.allCases, want)
    }

    func testInitialState() {
        XCTAssertEqual(coordinator.step, .welcome)
        XCTAssertTrue(coordinator.canContinue)
        XCTAssertFalse(coordinator.canGoBack)
        XCTAssertNil(coordinator.continueHint)
        XCTAssertEqual(coordinator.primaryButtonTitle, "Get Started")
    }

    func testContinueFromWelcomeMovesForwardToLanguage() {
        coordinator.continueFromCurrentStep(onComplete: {
            XCTFail("Completing from welcome should not finish onboarding")
        })

        XCTAssertEqual(coordinator.step, .language)
        XCTAssertTrue(coordinator.isNavigatingForward)
        XCTAssertTrue(coordinator.canGoBack)
        XCTAssertEqual(coordinator.primaryButtonTitle, "Continue")
    }

    func testGoBackFromLanguageReturnsToWelcome() {
        coordinator.continueFromCurrentStep(onComplete: {})
        XCTAssertEqual(coordinator.step, .language)

        coordinator.goBack()

        XCTAssertEqual(coordinator.step, .welcome)
        XCTAssertFalse(coordinator.isNavigatingForward)
        XCTAssertFalse(coordinator.canGoBack)
    }

    func testGoBackFromWelcomeIsNoOp() {
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .welcome)
    }
}
