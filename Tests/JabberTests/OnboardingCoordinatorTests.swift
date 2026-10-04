import XCTest
@testable import Jabber

/// Navigation tests for the onboarding flow. None of them continue from the
/// language step, which kicks off a real model download. Tests that start
/// further along select models through an isolated ModelManager, because
/// the selection APIs otherwise write to the shared TypedSettings store.
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
        let want: [OnboardingCoordinator.Step] = [.welcome, .language, .permissions, .hotkey, .modelDownload, .ready]
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
        coordinator.continueFromCurrentStep(
            onReachReady: {
                XCTFail("Leaving welcome should not reach the ready step")
            },
            onComplete: {
                XCTFail("Completing from welcome should not finish onboarding")
            }
        )

        XCTAssertEqual(coordinator.step, .language)
        XCTAssertTrue(coordinator.isNavigatingForward)
        XCTAssertTrue(coordinator.canGoBack)
        XCTAssertEqual(coordinator.primaryButtonTitle, "Continue")
    }

    func testGoBackFromLanguageReturnsToWelcome() {
        coordinator.continueFromCurrentStep(onReachReady: {}, onComplete: {})
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

    func testContinueReportsReachingReadyOnlyOnArrival() throws {
        let cases: [String: (
            start: OnboardingCoordinator.Step,
            wantStep: OnboardingCoordinator.Step,
            wantReachReadyCalls: Int,
            wantCompleteCalls: Int
        )] = [
            "welcome moves to language": (.welcome, .language, 0, 0),
            "hotkey step moves to model step": (.hotkey, .modelDownload, 0, 0),
            "model step moves to ready": (.modelDownload, .ready, 1, 0),
            "ready completes": (.ready, .ready, 0, 1),
        ]

        for (name, tc) in cases {
            let coordinator = try makeCoordinatorWithBuiltInModel(at: tc.start)
            var reachReadyCalls = 0
            var completeCalls = 0

            coordinator.continueFromCurrentStep(
                onReachReady: { reachReadyCalls += 1 },
                onComplete: { completeCalls += 1 }
            )

            XCTAssertEqual(coordinator.step, tc.wantStep, name)
            XCTAssertEqual(reachReadyCalls, tc.wantReachReadyCalls, name)
            XCTAssertEqual(completeCalls, tc.wantCompleteCalls, name)
        }
    }

    func testReturningToReadyAfterGoingBackReportsReachingReadyAgain() throws {
        // Going Back lets the user pick another model, so every arrival at
        // Ready must ask for a load again.
        let coordinator = try makeCoordinatorWithBuiltInModel(at: .modelDownload)
        var reachReadyCalls = 0

        coordinator.continueFromCurrentStep(onReachReady: { reachReadyCalls += 1 }, onComplete: {})
        coordinator.goBack()
        XCTAssertEqual(coordinator.step, .modelDownload)
        coordinator.continueFromCurrentStep(onReachReady: { reachReadyCalls += 1 }, onComplete: {})

        XCTAssertEqual(coordinator.step, .ready)
        XCTAssertEqual(reachReadyCalls, 2)
    }

    func testGoBackFromModelStepReturnsToHotkeyStep() throws {
        let coordinator = try makeCoordinatorWithBuiltInModel(at: .modelDownload)

        coordinator.goBack()

        XCTAssertEqual(coordinator.step, .hotkey)
    }

    func testSelectHotkeySavesAndAnnouncesIt() throws {
        let settings = try makeSettings()
        let coordinator = OnboardingCoordinator(settings: settings, step: .hotkey)
        let fn = HotkeyPreset.fn.shortcut
        let announced = expectation(
            forNotification: Constants.Notifications.hotkeyShortcutDidChange,
            object: nil
        ) { notification in
            notification.object as? HotkeyShortcut == fn
        }

        coordinator.selectHotkey(fn)

        wait(for: [announced], timeout: 1)
        XCTAssertEqual(coordinator.hotkeyShortcut, fn)
        XCTAssertEqual(settings.hotkeyShortcut, fn)
    }

    func testHotkeyStepNeedsTypingAccessForLoneModifiers() throws {
        // The coordinator has not refreshed permissions yet, so it treats
        // Accessibility as not granted.
        let coordinator = try OnboardingCoordinator(settings: makeSettings(), step: .hotkey)
        XCTAssertFalse(coordinator.isAccessibilityTrusted)

        let tests: [String: (shortcut: HotkeyShortcut, wantCanContinue: Bool, wantHint: String?)] = [
            "Option Space": (HotkeyPreset.optionSpace.shortcut, true, nil),
            "Right Option": (
                HotkeyPreset.rightOption.shortcut,
                false,
                "Right Option needs Typing Access — pick another hotkey"
            ),
            "Fn": (HotkeyPreset.fn.shortcut, false, "Fn needs Typing Access — pick another hotkey")
        ]

        for (name, tc) in tests {
            coordinator.selectHotkey(tc.shortcut)
            XCTAssertEqual(coordinator.canContinue, tc.wantCanContinue, name)
            XCTAssertEqual(coordinator.continueHint, tc.wantHint, name)
        }
    }

    func testCancelledDownloadDoesNotLeaveErrorMessage() {
        let modelId = coordinator.recommendedModelIdForSelectedLanguage()

        coordinator.handleModelDownloadState(ModelDownloadState(
            modelId: modelId,
            progress: 0.5,
            status: "Download failed: Greendale Community College",
            phase: .failed,
            errorDescription: "Network went full Señor Chang",
            isCancelled: false
        ))
        XCTAssertEqual(coordinator.downloadErrorMessage, "Network went full Señor Chang")

        coordinator.handleModelDownloadState(ModelDownloadState(
            modelId: modelId,
            progress: 0.5,
            status: "Download cancelled: Greendale Community College",
            phase: .failed,
            errorDescription: nil,
            isCancelled: true
        ))

        XCTAssertNil(coordinator.downloadErrorMessage)
    }

    /// A settings store backed by its own defaults suite.
    private func makeSettings() throws -> SettingsStore {
        let suiteName = "JabberTests.OnboardingCoordinator.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return SettingsStore(userDefaults: userDefaults)
    }

    /// Parks a coordinator on `step` with built-in Apple Speech selected, so
    /// the model step can continue without a download. The ModelManager and
    /// hotkey use their own defaults suite and an empty cache directory.
    private func makeCoordinatorWithBuiltInModel(
        at step: OnboardingCoordinator.Step
    ) throws -> OnboardingCoordinator {
        let settings = try makeSettings()
        // Start on a different model so selectModel goes through the
        // isolated ModelManager instead of falling back to TypedSettings.
        settings[.selectedModel] = AppMode.nemotronModelId
        let modelManager = ModelManager(
            settings: settings,
            cacheBaseURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("JabberOnboardingCoordinatorTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        let coordinator = OnboardingCoordinator(modelManager: modelManager, settings: settings, step: step)
        coordinator.selectModel(AppMode.appleSpeechModelId)
        XCTAssertEqual(settings[.selectedModel], AppMode.appleSpeechModelId)
        return coordinator
    }
}
