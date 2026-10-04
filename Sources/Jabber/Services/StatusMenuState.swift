import Foundation

/// What the status menu shows for the current app state. Pure so the menu's
/// dynamic items are testable without AppKit; AppDelegate applies it each time
/// the menu opens.
struct StatusMenuState: Equatable {
    /// Longest last-transcript preview shown under the menu item.
    static let previewLength = 40
    /// Most saved transcripts listed under Recent Transcripts.
    static let recentTranscriptCount = 5

    /// A saved transcript offered under Recent Transcripts.
    struct RecentTranscript: Equatable {
        let id: UUID
        /// One-line preview used as the item's title.
        let title: String
        /// What choosing the item delivers.
        let text: String
        let timestamp: Date
        let appName: String?
    }

    var header: String
    /// Start, stop, or cancel the session, depending on its phase.
    var dictationItemTitle: String
    var lastTranscriptItemTitle: String
    var lastTranscriptPreview: String?
    var canDeliverLastTranscript: Bool
    /// Newest saved transcripts; empty hides Recent Transcripts.
    var recentTranscripts: [RecentTranscript]
    var canDeliverRecentTranscripts: Bool
    /// Retry and Discard for a kept failed dictation.
    var showsFailedDictationItems: Bool
    var canActOnFailedDictation: Bool
    var showsRetryModelLoad: Bool

    /// - Parameter progress: Download or load progress, when known.
    static func resolve(
        appState: AppDelegate.AppState,
        progress: Double?,
        hotkeyDisplay: String,
        isSetupPending: Bool,
        dictationState: DictationCoordinator.State,
        lastTranscript: String?,
        historyEntries: [DictationHistoryEntry],
        isHistoryEnabled: Bool,
        outputMode: TypingService.OutputMode,
        hasFailedDictation: Bool,
        canStartSession: Bool,
        hasModelLoadFailed: Bool
    ) -> StatusMenuState {
        StatusMenuState(
            header: header(for: appState, progress: progress, hotkeyDisplay: hotkeyDisplay, isSetupPending: isSetupPending),
            dictationItemTitle: dictationItemTitle(for: dictationState),
            lastTranscriptItemTitle: outputMode == .clipboard ? "Copy Last Transcript" : "Paste Last Transcript",
            lastTranscriptPreview: lastTranscript.map(preview),
            // Delivering mid-session would interleave with the new dictation.
            canDeliverLastTranscript: lastTranscript != nil && dictationState == .idle,
            recentTranscripts: isHistoryEnabled ? recentTranscripts(from: historyEntries) : [],
            canDeliverRecentTranscripts: dictationState == .idle,
            showsFailedDictationItems: hasFailedDictation,
            canActOnFailedDictation: hasFailedDictation && canStartSession,
            showsRetryModelLoad: hasModelLoadFailed
        )
    }

    /// The newest entries with text, newest first.
    static func recentTranscripts(from entries: [DictationHistoryEntry]) -> [RecentTranscript] {
        entries.lazy
            .compactMap { entry -> RecentTranscript? in
                let text = entry.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecentTranscript(
                    id: entry.id,
                    title: preview(text),
                    text: text,
                    timestamp: entry.timestamp,
                    appName: entry.appName
                )
            }
            .prefix(recentTranscriptCount)
            .map { $0 }
    }

    /// One line of the transcript, cut to `previewLength` characters.
    static func preview(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard oneLine.count > previewLength else { return oneLine }
        return oneLine.prefix(previewLength - 1) + "…"
    }

    private static func header(
        for appState: AppDelegate.AppState,
        progress: Double?,
        hotkeyDisplay: String,
        isSetupPending: Bool
    ) -> String {
        switch appState {
        case .downloading:
            guard let progress else { return "Preparing Speech Model…" }
            return "Preparing Speech Model… \(Int(progress * 100))%"
        case .ready:
            return "Ready to Dictate — \(hotkeyDisplay)"
        case .recording:
            return "Recording…"
        case .transcribing:
            return "Transcribing…"
        case .error:
            // Before setup finishes no model was ever chosen, so "unavailable"
            // would read as a failure.
            return isSetupPending ? "Finish Setup to Dictate" : "Model Unavailable"
        }
    }

    private static func dictationItemTitle(for state: DictationCoordinator.State) -> String {
        switch state {
        case .idle:
            return "Start Dictation"
        case .recording:
            return "Stop Dictation"
        case .transcribing:
            return "Cancel Dictation"
        }
    }
}
