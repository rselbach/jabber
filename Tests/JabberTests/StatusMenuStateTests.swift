import XCTest
@testable import Jabber

@MainActor
final class StatusMenuStateTests: XCTestCase {
    func testHeaderNamesTheCurrentState() {
        let cases: [String: (appState: AppDelegate.AppState, isSetupPending: Bool, want: String)] = [
            "preparing a model": (.downloading, false, "Preparing Speech Model…"),
            "ready": (.ready, false, "Ready to Dictate — ⌥ Space"),
            "recording": (.recording, false, "Recording…"),
            "transcribing": (.transcribing, false, "Transcribing…"),
            "no model after setup": (.error, false, "Model Unavailable"),
            "no model before setup": (.error, true, "Finish Setup to Dictate")
        ]

        for (name, tc) in cases {
            let got = StatusMenuState.resolve(
                appState: tc.appState,
                hotkeyDisplay: "⌥ Space",
                isSetupPending: tc.isSetupPending,
                hasFailedDictation: false,
                canStartSession: true,
                hasModelLoadFailed: false
            )
            XCTAssertEqual(got.header, tc.want, name)
        }
    }

    func testRecoveryItemsFollowFailures() {
        let cases: [String: (
            hasFailedDictation: Bool,
            canStartSession: Bool,
            hasModelLoadFailed: Bool,
            wantShowsFailedDictation: Bool,
            wantCanActOnFailedDictation: Bool,
            wantShowsRetryModelLoad: Bool
        )] = [
            "nothing failed": (false, true, false, false, false, false),
            "failed dictation while idle": (true, true, false, true, true, false),
            "failed dictation while a session runs": (true, false, false, true, false, false),
            "model load failed": (false, true, true, false, false, true),
            "both failed": (true, true, true, true, true, true)
        ]

        for (name, tc) in cases {
            let got = StatusMenuState.resolve(
                appState: .ready,
                hotkeyDisplay: "⌥ Space",
                isSetupPending: false,
                hasFailedDictation: tc.hasFailedDictation,
                canStartSession: tc.canStartSession,
                hasModelLoadFailed: tc.hasModelLoadFailed
            )
            XCTAssertEqual(got.showsFailedDictationItems, tc.wantShowsFailedDictation, name)
            XCTAssertEqual(got.canActOnFailedDictation, tc.wantCanActOnFailedDictation, name)
            XCTAssertEqual(got.showsRetryModelLoad, tc.wantShowsRetryModelLoad, name)
        }
    }
}
