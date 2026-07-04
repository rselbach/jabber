import Foundation

/// Application-wide constants and notification names
enum Constants {
    /// Notification names used throughout the application
    enum Notifications {
        /// Posted when the selected transcription model changes
        static let modelDidChange = Notification.Name("com.rselbach.jabber.modelDidChange")

        /// Posted when a model download starts/progresses/finishes
        static let modelDownloadStateDidChange = Notification.Name("com.rselbach.jabber.modelDownloadStateDidChange")

        /// Posted when the configured hotkey shortcut changes. `object` is the
        /// new `HotkeyShortcut`. Observed by AppDelegate to re-register the
        /// global hotkey.
        static let hotkeyShortcutDidChange = Notification.Name("com.rselbach.jabber.hotkeyShortcutDidChange")

        /// Posted when the hotkey activation mode changes. `object` is the new
        /// `HotkeyActivationMode`. Read at key-down time, so no re-registration
        /// is needed — kept distinct from `hotkeyShortcutDidChange` so observers
        /// don't have to type-sniff the payload.
        static let hotkeyActivationModeDidChange = Notification.Name("com.rselbach.jabber.hotkeyActivationModeDidChange")

        /// Posted while the Settings UI is recording a new hotkey
        static let hotkeyCaptureDidBegin = Notification.Name("com.rselbach.jabber.hotkeyCaptureDidBegin")
        static let hotkeyCaptureDidEnd = Notification.Name("com.rselbach.jabber.hotkeyCaptureDidEnd")

        /// Posted when the user asks to run onboarding from Settings
        static let onboardingDidRequest = Notification.Name("com.rselbach.jabber.onboardingDidRequest")

        /// Posted to deep-link the main window to a specific sidebar section.
        /// `object` is the `MainWindowView.Section` to select. Observed by
        /// AppDelegate (which shows the window) and MainWindowView (which sets
        /// the sidebar selection when the window is already open). Used so a
        /// menu item — Cmd-, (General), the status-menu Settings, Vocabulary —
        /// can land on a page even when the window instance already exists (the
        /// window is retained across close/reopen, so its initial selection is
        /// only honored at creation time).
        static let mainWindowSectionDidRequest = Notification.Name("com.rselbach.jabber.mainWindowSectionDidRequest")
    }

    /// Languages supported by Qwen3-ASR (per the model card).
    /// Codes are passed verbatim as a decoder prompt prefix; unsupported codes
    /// produce nonsense text and unpredictable results.
    static let languages: [String: String] = [
        "arabic": "ar",
        "cantonese": "yue",
        "castilian": "es",
        "chinese": "zh",
        "czech": "cs",
        "danish": "da",
        "dutch": "nl",
        "english": "en",
        "farsi": "fa",
        "filipino": "fil",
        "finnish": "fi",
        "flemish": "nl",
        "french": "fr",
        "german": "de",
        "greek": "el",
        "hindi": "hi",
        "hungarian": "hu",
        "indonesian": "id",
        "italian": "it",
        "japanese": "ja",
        "korean": "ko",
        "macedonian": "mk",
        "malay": "ms",
        "mandarin": "zh",
        "persian": "fa",
        "polish": "pl",
        "portuguese": "pt",
        "romanian": "ro",
        "russian": "ru",
        "spanish": "es",
        "swedish": "sv",
        "tagalog": "fil",
        "thai": "th",
        "turkish": "tr",
        "vietnamese": "vi"
    ]

    /// some language codes have multiple names; pick one for UI
    private static let preferredLanguageNameByCode: [String: String] = [
        "es": "spanish",
        "fa": "persian",
        "fil": "filipino",
        "nl": "dutch",
        "ro": "romanian",
        "zh": "chinese"
    ]

    private static let languageDisplayNameByCode: [String: String] = {
        var byCode: [String: String] = [:]

        for (name, code) in languages {
            if let preferred = preferredLanguageNameByCode[code], name == preferred {
                byCode[code] = name
                continue
            }
            if byCode[code] == nil {
                byCode[code] = name
            }
        }

        // ensure preferred names win deterministically
        for (code, preferredName) in preferredLanguageNameByCode {
            if languages[preferredName] == code {
                byCode[code] = preferredName
            }
        }

        return byCode
    }()

    /// Pre-sorted languages for UI display (cached to avoid repeated sorting)
    static let sortedLanguages: [(name: String, code: String)] = languageDisplayNameByCode
        .map { (name: $0.value.capitalized, code: $0.key) }
        .sorted { $0.name < $1.name }

    /// Valid language codes for validation (every code present in the languages dict)
    static let validLanguageCodes: Set<String> = Set(languages.values)

    /// Default language based on system locale, falls back to "auto" if unsupported.
    /// Computed on each access so it follows live system locale changes.
    static var defaultLanguage: String {
        guard let languageCode = Locale.current.language.languageCode?.identifier else {
            return "auto"
        }

        if validLanguageCodes.contains(languageCode) {
            return languageCode
        }

        return "auto"
    }
}
