import FluidAudio
import Foundation

enum AppMode {
    static let parakeetModelId = "parakeet-tdt-v2"
    static let parakeetMultilingualModelId = "parakeet-ultra"
    static let parakeetJapaneseModelId = "parakeet-ja"
    static let parakeetUnifiedModelId = "parakeet-unified"
    static let appleSpeechModelId = "apple-speech"

    /// Languages Parakeet Ultra transcribes: those of NVIDIA's Parakeet TDT v3,
    /// which it was post-trained from. The wider set is deliberate: it also
    /// names languages Jabber does not offer yet, so adding one to
    /// `Constants.languages` routes to Ultra for free.
    static let parakeetMultilingualLanguageCodes: Set<String> = [
        "be", "bg", "bs", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
        "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk",
        "sl", "sr", "sv", "uk"
    ]

    /// Languages Apple Speech transcribes: the union of SpeechTranscriber's and
    /// DictationTranscriber's supported locales on macOS 27. Like the Parakeet
    /// list, it names languages Jabber does not offer yet. The provider still
    /// asks the Speech framework at load time, which has the final say.
    static let appleSpeechLanguageCodes: Set<String> = [
        "ar", "bn", "ca", "cs", "da", "de", "el", "en", "es", "fi", "fr", "gu",
        "he", "hi", "hr", "hu", "id", "it", "ja", "kn", "ko", "ks", "mai", "ml",
        "mr", "ms", "nb", "ne", "nl", "or", "pa", "pl", "pt", "ro", "ru", "sk",
        "sv", "ta", "te", "th", "tr", "uk", "ur", "vi", "yue", "zh"
    ]

    enum ModelFamily: String, CaseIterable {
        case parakeetTDT
        case parakeetUnified
        case appleSpeech
    }

    /// Where a model's files come from.
    enum ModelSource {
        /// Downloaded and loaded by FluidAudio, which keeps each repository in
        /// a folder it names.
        case fluidAudio(Repo)
        /// Ships with macOS.
        case system
    }

    struct ModelDefinition: Identifiable {
        let id: String
        let family: ModelFamily
        let source: ModelSource
        let name: String
        let description: String
        let sizeHint: String
        let supportedLanguageCodes: Set<String>
        let license: String
        let licenseUrl: String
        let attribution: String

        var isBuiltIn: Bool {
            if case .system = source {
                return true
            }
            return false
        }
    }

    static let modelDefinitions: [ModelDefinition] = [
        .init(
            id: parakeetModelId,
            family: .parakeetTDT,
            source: .fluidAudio(.parakeetV2),
            name: "Parakeet TDT v2",
            description: "NVIDIA Parakeet TDT v2 — fast, accurate English transcription",
            sizeHint: "~443MB",
            supportedLanguageCodes: ["en"],
            license: "CC BY 4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet TDT 0.6B v2 by NVIDIA; CoreML conversion by FluidInference"
        ),
        .init(
            id: parakeetMultilingualModelId,
            family: .parakeetTDT,
            source: .fluidAudio(.parakeetUltra),
            name: "Parakeet Ultra",
            description: "Moondream's retrained Parakeet v3 — 25 European languages, fewer errors at the same speed",
            sizeHint: "~617MB",
            supportedLanguageCodes: parakeetMultilingualLanguageCodes,
            license: "CC BY 4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet Ultra by Moondream, post-trained from NVIDIA Parakeet TDT 0.6B v3; CoreML conversion by FluidInference"
        ),
        .init(
            id: parakeetJapaneseModelId,
            family: .parakeetTDT,
            source: .fluidAudio(.parakeetJa),
            name: "Parakeet Japanese",
            description: "NVIDIA Parakeet 0.6B tuned for Japanese",
            sizeHint: "~606MB",
            supportedLanguageCodes: ["ja"],
            license: "CC BY 4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet 0.6B Japanese by NVIDIA; CoreML conversion by FluidInference"
        ),
        .init(
            id: parakeetUnifiedModelId,
            family: .parakeetUnified,
            source: .fluidAudio(.parakeetUnified),
            name: "Parakeet Unified",
            description: "NVIDIA Parakeet Unified — English, transcribed live as you speak",
            sizeHint: "~590MB",
            supportedLanguageCodes: ["en"],
            license: "NVIDIA Open Model License",
            licenseUrl: "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/",
            attribution: "Parakeet Unified 0.6B by NVIDIA; CoreML conversion by FluidInference"
        ),
        .init(
            id: appleSpeechModelId,
            family: .appleSpeech,
            source: .system,
            name: "Apple Speech",
            description: "Built-in macOS speech recognition — no download required",
            sizeHint: "Built-in",
            supportedLanguageCodes: appleSpeechLanguageCodes,
            license: "Apple System",
            licenseUrl: "https://www.apple.com/legal/sla/",
            attribution: "Apple Speech Framework (macOS 26+)"
        )
    ]

    static func modelDefinition(for modelId: String) -> ModelDefinition? {
        modelDefinitions.first { $0.id == modelId }
    }

    static func family(for modelId: String) -> ModelFamily? {
        modelDefinition(for: modelId)?.family
    }
}
