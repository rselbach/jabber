import XCTest
@testable import Jabber

@MainActor
final class StatusMenuStateTests: XCTestCase {
    private func resolve(
        appState: AppDelegate.AppState = .ready,
        progress: Double? = nil,
        isSetupPending: Bool = false,
        dictationState: DictationCoordinator.State = .idle,
        lastTranscript: String? = nil,
        historyEntries: [DictationHistoryEntry] = [],
        isHistoryEnabled: Bool = true,
        outputMode: TypingService.OutputMode = .directTyping,
        hasFailedDictation: Bool = false,
        canStartSession: Bool = true,
        hasModelLoadFailed: Bool = false
    ) -> StatusMenuState {
        StatusMenuState.resolve(
            appState: appState,
            progress: progress,
            hotkeyDisplay: "⌥ Space",
            isSetupPending: isSetupPending,
            dictationState: dictationState,
            lastTranscript: lastTranscript,
            historyEntries: historyEntries,
            isHistoryEnabled: isHistoryEnabled,
            outputMode: outputMode,
            hasFailedDictation: hasFailedDictation,
            canStartSession: canStartSession,
            hasModelLoadFailed: hasModelLoadFailed
        )
    }

    func testHeaderNamesTheCurrentState() {
        let cases: [String: (appState: AppDelegate.AppState, progress: Double?, isSetupPending: Bool, want: String)] = [
            "preparing a model": (.downloading, nil, false, "Preparing Speech Model…"),
            "downloading with known progress": (.downloading, 0.426, false, "Preparing Speech Model… 42%"),
            "ready": (.ready, nil, false, "Ready to Dictate — ⌥ Space"),
            "recording": (.recording, nil, false, "Recording…"),
            "transcribing": (.transcribing, nil, false, "Transcribing…"),
            "no model after setup": (.error, nil, false, "Model Unavailable"),
            "no model before setup": (.error, nil, true, "Finish Setup to Dictate")
        ]

        for (name, tc) in cases {
            let got = resolve(appState: tc.appState, progress: tc.progress, isSetupPending: tc.isSetupPending)
            XCTAssertEqual(got.header, tc.want, name)
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

    func testRecentTranscriptsListTheNewestSavedText() {
        let entries = [
            historyEntry("  Troy and Abed in the morning  ", app: "Greendale Messenger"),
            historyEntry("   "),
            historyEntry("Six seasons and a movie"),
            historyEntry("Cool. Cool cool cool."),
            historyEntry("Streets ahead"),
            historyEntry("Pop pop"),
            historyEntry("Señor Chang")
        ]
        let cases: [String: (isHistoryEnabled: Bool, state: DictationCoordinator.State, wantTitles: [String], wantCanDeliver: Bool)] = [
            "five newest with text": (
                true,
                .idle,
                ["Troy and Abed in the morning", "Six seasons and a movie", "Cool. Cool cool cool.", "Streets ahead", "Pop pop"],
                true
            ),
            "history off": (false, .idle, [], true),
            "busy recording": (
                true,
                .recording,
                ["Troy and Abed in the morning", "Six seasons and a movie", "Cool. Cool cool cool.", "Streets ahead", "Pop pop"],
                false
            )
        ]

        for (name, tc) in cases {
            let got = resolve(dictationState: tc.state, historyEntries: entries, isHistoryEnabled: tc.isHistoryEnabled)
            XCTAssertEqual(got.recentTranscripts.map(\.title), tc.wantTitles, name)
            XCTAssertEqual(got.canDeliverRecentTranscripts, tc.wantCanDeliver, name)
        }

        let first = resolve(historyEntries: entries).recentTranscripts.first
        XCTAssertEqual(first?.text, "Troy and Abed in the morning")
        XCTAssertEqual(first?.appName, "Greendale Messenger")
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

    private func historyEntry(_ transcript: String, app: String? = nil) -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            duration: 1,
            sampleRate: 16_000,
            modelID: AppMode.parakeetModelId,
            modelName: "Parakeet TDT v2",
            language: "en",
            transcript: transcript,
            directoryName: "entry",
            audioFilename: nil,
            audioByteCount: 0,
            appName: app
        )
    }
}
