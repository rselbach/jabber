import Foundation

/// What the status menu shows for the current app state. Pure so the menu's
/// dynamic items are testable without AppKit; AppDelegate applies it each time
/// the menu opens.
struct StatusMenuState: Equatable {
    var header: String
    /// Retry and Discard for a kept failed dictation.
    var showsFailedDictationItems: Bool
    var canActOnFailedDictation: Bool
    var showsRetryModelLoad: Bool

    static func resolve(
        appState: AppDelegate.AppState,
        hotkeyDisplay: String,
        isSetupPending: Bool,
        hasFailedDictation: Bool,
        canStartSession: Bool,
        hasModelLoadFailed: Bool
    ) -> StatusMenuState {
        StatusMenuState(
            header: header(for: appState, hotkeyDisplay: hotkeyDisplay, isSetupPending: isSetupPending),
            showsFailedDictationItems: hasFailedDictation,
            canActOnFailedDictation: hasFailedDictation && canStartSession,
            showsRetryModelLoad: hasModelLoadFailed
        )
    }

    private static func header(
        for appState: AppDelegate.AppState,
        hotkeyDisplay: String,
        isSetupPending: Bool
    ) -> String {
        switch appState {
        case .downloading:
            return "Preparing Speech Model…"
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
}
