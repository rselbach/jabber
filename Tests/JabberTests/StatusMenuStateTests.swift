import XCTest
@testable import Jabber

@MainActor
final class StatusMenuStateTests: XCTestCase {
    private func resolve(
        appState: AppDelegate.AppState = .ready,
        isSetupPending: Bool = false,
        dictationState: DictationCoordinator.State = .idle,
        lastTranscript: String? = nil,
        outputMode: TypingService.OutputMode = .directTyping,
        hasFailedDictation: Bool = false,
        canStartSession: Bool = true,
        hasModelLoadFailed: Bool = false
    ) -> StatusMenuState {
        StatusMenuState.resolve(
            appState: appState,
            hotkeyDisplay: "⌥ Space",
            isSetupPending: isSetupPending,
            dictationState: dictationState,
            lastTranscript: lastTranscript,
            outputMode: outputMode,
            hasFailedDictation: hasFailedDictation,
            canStartSession: canStartSession,
            hasModelLoadFailed: hasModelLoadFailed
        )
    }

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
            XCTAssertEqual(resolve(appState: tc.appState, isSetupPending: tc.isSetupPending).header, tc.want, name)
        }
    }

    func testDictationItemFollowsTheSession() {
        let cases: [String: (state: DictationCoordinator.State, want: String)] = [
            "idle": (.idle, "Start Dictation"),
            "recording": (.recording, "Stop Dictation"),
            "transcribing": (.transcribing(sessionID: UUID()), "Cancel Dictation")
        ]

        for (name, tc) in cases {
            XCTAssertEqual(resolve(dictationState: tc.state).dictationItemTitle, tc.want, name)
        }
    }

    func testLastTranscriptItem() {
        let cases: [String: (
            state: DictationCoordinator.State,
            lastTranscript: String?,
            outputMode: TypingService.OutputMode,
            wantTitle: String,
            wantPreview: String?,
            wantEnabled: Bool
        )] = [
            "nothing dictated yet": (.idle, nil, .directTyping, "Paste Last Transcript", nil, false),
            "typing output": (.idle, "Troy Barnes", .directTyping, "Paste Last Transcript", "Troy Barnes", true),
            "clipboard output": (.idle, "Troy Barnes", .clipboard, "Copy Last Transcript", "Troy Barnes", true),
            "during a session": (.recording, "Troy Barnes", .directTyping, "Paste Last Transcript", "Troy Barnes", false)
        ]

        for (name, tc) in cases {
            let got = resolve(dictationState: tc.state, lastTranscript: tc.lastTranscript, outputMode: tc.outputMode)
            XCTAssertEqual(got.lastTranscriptItemTitle, tc.wantTitle, name)
            XCTAssertEqual(got.lastTranscriptPreview, tc.wantPreview, name)
            XCTAssertEqual(got.canDeliverLastTranscript, tc.wantEnabled, name)
        }
    }

    func testPreviewIsOneShortLine() {
        let cases: [String: (text: String, want: String)] = [
            "short": ("Troy Barnes", "Troy Barnes"),
            "line breaks and runs of spaces collapse": ("Troy\n\nand   Abed", "Troy and Abed"),
            "exactly the limit": (String(repeating: "a", count: 40), String(repeating: "a", count: 40)),
            "over the limit": (
                "Greendale Community College is where Troy and Abed met",
                "Greendale Community College is where Tr…"
            )
        ]

        for (name, tc) in cases {
            let got = StatusMenuState.preview(tc.text)
            XCTAssertEqual(got, tc.want, name)
            XCTAssertLessThanOrEqual(got.count, StatusMenuState.previewLength, name)
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
            let got = resolve(
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
