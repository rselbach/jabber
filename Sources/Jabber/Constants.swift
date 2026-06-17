import Foundation

/// Application-wide constants and notification names
enum Constants {
    /// Notification names used throughout the application
    enum Notifications {
        /// Posted when the selected transcription model changes
        static let modelDidChange = Notification.Name("com.rselbach.jabber.modelDidChange")

        /// Posted when a model download starts/progresses/finishes
        static let modelDownloadStateDidChange = Notification.Name("com.rselbach.jabber.modelDownloadStateDidChange")

        /// Posted when the global dictation hotkey changes
        static let hotkeyDidChange = Notification.Name("com.rselbach.jabber.hotkeyDidChange")

        /// Posted while the Settings UI is recording a new hotkey
        static let hotkeyCaptureDidBegin = Notification.Name("com.rselbach.jabber.hotkeyCaptureDidBegin")
        static let hotkeyCaptureDidEnd = Notification.Name("com.rselbach.jabber.hotkeyCaptureDidEnd")
    }

    /// Supported transcription languages
    static let languages: [String: String] = [
        "afrikaans": "af", "albanian": "sq", "amharic": "am", "arabic": "ar",
        "armenian": "hy", "assamese": "as", "azerbaijani": "az", "bashkir": "ba",
        "basque": "eu", "belarusian": "be", "bengali": "bn", "bosnian": "bs",
        "breton": "br", "bulgarian": "bg", "burmese": "my", "cantonese": "yue",
        "castilian": "es", "catalan": "ca", "chinese": "zh", "croatian": "hr",
        "czech": "cs", "danish": "da", "dutch": "nl", "english": "en",
        "estonian": "et", "faroese": "fo", "finnish": "fi", "flemish": "nl",
        "french": "fr", "galician": "gl", "georgian": "ka", "german": "de",
        "greek": "el", "gujarati": "gu", "haitian": "ht", "haitian creole": "ht",
        "hausa": "ha", "hawaiian": "haw", "hebrew": "he", "hindi": "hi",
        "hungarian": "hu", "icelandic": "is", "indonesian": "id", "italian": "it",
        "japanese": "ja", "javanese": "jw", "kannada": "kn", "kazakh": "kk",
        "khmer": "km", "korean": "ko", "lao": "lo", "latin": "la",
        "latvian": "lv", "letzeburgesch": "lb", "lingala": "ln", "lithuanian": "lt",
        "luxembourgish": "lb", "macedonian": "mk", "malagasy": "mg", "malay": "ms",
        "malayalam": "ml", "maltese": "mt", "mandarin": "zh", "maori": "mi",
        "marathi": "mr", "moldavian": "ro", "moldovan": "ro", "mongolian": "mn",
        "myanmar": "my", "nepali": "ne", "norwegian": "no", "nynorsk": "nn",
        "occitan": "oc", "panjabi": "pa", "pashto": "ps", "persian": "fa",
        "polish": "pl", "portuguese": "pt", "punjabi": "pa", "pushto": "ps",
        "romanian": "ro", "russian": "ru", "sanskrit": "sa", "serbian": "sr",
        "shona": "sn", "sindhi": "sd", "sinhala": "si", "sinhalese": "si",
        "slovak": "sk", "slovenian": "sl", "somali": "so", "spanish": "es",
        "sundanese": "su", "swahili": "sw", "swedish": "sv", "tagalog": "tl",
        "tajik": "tg", "tamil": "ta", "tatar": "tt", "telugu": "te",
        "thai": "th", "tibetan": "bo", "turkish": "tr", "turkmen": "tk",
        "ukrainian": "uk", "urdu": "ur", "uzbek": "uz", "valencian": "ca",
        "vietnamese": "vi", "welsh": "cy", "yiddish": "yi", "yoruba": "yo"
    ]

    // some language codes have multiple names; pick one for UI
    private static let preferredLanguageNameByCode: [String: String] = [
        "ca": "catalan",
        "es": "spanish",
        "ht": "haitian creole",
        "lb": "luxembourgish",
        "my": "burmese",
        "nl": "dutch",
        "pa": "punjabi",
        "ps": "pashto",
        "ro": "romanian",
        "si": "sinhala",
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
    static let sortedLanguages: [(name: String, code: String)] = {
        languageDisplayNameByCode
            .map { (name: $0.value.capitalized, code: $0.key) }
            .sorted { $0.name < $1.name }
    }()

    /// Valid language codes for validation (every code present in the languages dict)
    static let validLanguageCodes: Set<String> = Set(languages.values)

    /// Default language based on system locale, falls back to "auto" if unsupported
    static let defaultLanguage: String = {
        guard let languageCode = Locale.current.language.languageCode?.identifier else {
            return "auto"
        }

        // Check if the system language is supported by the transcription model
        if validLanguageCodes.contains(languageCode) {
            return languageCode
        }

        return "auto"
    }()

}
