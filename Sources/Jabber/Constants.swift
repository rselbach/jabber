import Foundation
import os

/// Application-wide constants and notification names
enum Constants {
    /// Notification names used throughout the application
    enum Notifications {
        /// Posted when the selected Whisper model changes
        static let modelDidChange = Notification.Name("com.rselbach.jabber.modelDidChange")
    }

    /// Supported Whisper transcription languages (from WhisperKit)
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

    /// Pre-sorted languages for UI display (cached to avoid repeated sorting)
    static let sortedLanguages: [(name: String, code: String)] = {
        languages
            .map { (name: $0.key.capitalized, code: $0.value) }
            .sorted { $0.name < $1.name }
    }()

    /// Valid language codes for validation (includes all unique codes from languages dict)
    static let validLanguageCodes: Set<String> = Set(languages.values)

    /// Default language based on system locale, falls back to "auto" if unsupported
    static let defaultLanguage: String = {
        guard let languageCode = Locale.current.language.languageCode?.identifier else {
            return "auto"
        }

        // Check if the system language is supported by Whisper
        if validLanguageCodes.contains(languageCode) {
            return languageCode
        }

        return "auto"
    }()

    /// Helper for locating Whisper model files
    enum ModelPaths {
        private static let repoName = "argmaxinc/whisperkit-coreml"
        private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "ModelPaths")

        /// Returns the base directory where models are stored
        static func modelsBaseURL() -> URL? {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return docs
                .appendingPathComponent("huggingface")
                .appendingPathComponent("models")
                .appendingPathComponent(repoName)
        }

        /// Finds the local folder for a specific model ID
        /// - Parameter modelId: The model identifier (e.g., "base", "tiny", "large-v3")
        /// - Returns: URL to the model folder if found, nil otherwise
        static func localModelFolder(for modelId: String) -> URL? {
            guard let base = modelsBaseURL() else { return nil }

            let fm = FileManager.default
            guard fm.fileExists(atPath: base.path) else { return nil }

            let contents: [String]
            do {
                contents = try fm.contentsOfDirectory(atPath: base.path)
            } catch {
                logger.warning("Failed to read model directory at \(base.path): \(error.localizedDescription)")
                return nil
            }

            let suffixPattern = "-\(modelId)"

            for folder in contents {
                let matchesExactSuffix = folder.hasSuffix(suffixPattern)
                let matchesExactName = folder == modelId

                guard matchesExactSuffix || matchesExactName else {
                    continue
                }

                let folderURL = base.appendingPathComponent(folder)
                let configPath = folderURL.appendingPathComponent("config.json")

                guard fm.fileExists(atPath: configPath.path) else {
                    continue
                }

                return folderURL
            }

            return nil
        }
    }
}
