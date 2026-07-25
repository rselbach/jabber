import Foundation

enum AppMode {
    static let parakeetModelId = "parakeet-tdt-v2"
    static let parakeetMultilingualModelId = "parakeet-tdt-v3"
    static let parakeetJapaneseModelId = "parakeet-ja"
    static let nemotronModelId = "nemotron"
    static let appleSpeechModelId = "apple-speech"

    /// Languages Parakeet TDT v3 transcribes, from NVIDIA's model card. The
    /// wider set is deliberate: it also names languages Jabber does not offer
    /// yet, so adding one to `Constants.languages` routes to v3 for free.
    static let parakeetMultilingualLanguageCodes: Set<String> = [
        "be", "bg", "bs", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
        "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk",
        "sl", "sr", "sv", "uk"
    ]

    enum ModelFamily: String, CaseIterable {
        case parakeetTDT
        case nemotronASR
        case appleSpeech
    }

    struct ModelDefinition: Identifiable {
        let id: String
        let family: ModelFamily
        let huggingFaceModelId: String
        let name: String
        let description: String
        let sizeHint: String
        let supportedLanguageCodes: Set<String>?
        let license: String
        let licenseUrl: String
        let attribution: String
        let isBuiltIn: Bool

        var supportsAllLanguages: Bool {
            supportedLanguageCodes == nil
        }
    }

    static let modelDefinitions: [ModelDefinition] = [
        .init(
            id: parakeetModelId,
            family: .parakeetTDT,
            huggingFaceModelId: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
            name: "Parakeet TDT v2",
            description: "NVIDIA Parakeet TDT v2 — fast, accurate English transcription",
            sizeHint: "~443MB",
            supportedLanguageCodes: ["en"],
            license: "CC BY 4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet TDT 0.6B v2 by NVIDIA; CoreML conversion by FluidInference",
            isBuiltIn: false
        ),
        .init(
            id: parakeetMultilingualModelId,
            family: .parakeetTDT,
            huggingFaceModelId: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            name: "Parakeet TDT v3",
            description: "NVIDIA Parakeet TDT v3 — 25 European languages at v2's speed",
            sizeHint: "~461MB",
            supportedLanguageCodes: parakeetMultilingualLanguageCodes,
            license: "CC BY 4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet TDT 0.6B v3 by NVIDIA; CoreML conversion by FluidInference",
            isBuiltIn: false
        ),
        .init(
            id: parakeetJapaneseModelId,
            family: .parakeetTDT,
            huggingFaceModelId: "FluidInference/parakeet-0.6b-ja-coreml",
            name: "Parakeet Japanese",
            description: "NVIDIA Parakeet 0.6B tuned for Japanese",
            sizeHint: "~606MB",
            supportedLanguageCodes: ["ja"],
            license: "CC BY 4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet 0.6B Japanese by NVIDIA; CoreML conversion by FluidInference",
            isBuiltIn: false
        ),
        .init(
            id: nemotronModelId,
            family: .nemotronASR,
            huggingFaceModelId: "aufklarer/Nemotron-Speech-Streaming-0.6B-CoreML-INT8",
            name: "Nemotron",
            description: "NVIDIA Nemotron — English-only, native punctuation & capitalization",
            sizeHint: "~600MB",
            supportedLanguageCodes: ["en"],
            license: "OpenMDW-1.1",
            licenseUrl: "https://www.openmodeldefinition.org/",
            attribution: "Nemotron Speech Streaming by NVIDIA",
            isBuiltIn: false
        ),
        .init(
            id: appleSpeechModelId,
            family: .appleSpeech,
            huggingFaceModelId: "",
            name: "Apple Speech",
            description: "Built-in macOS speech recognition — no download required",
            sizeHint: "Built-in",
            supportedLanguageCodes: nil,
            license: "Apple System",
            licenseUrl: "https://www.apple.com/legal/sla/",
            attribution: "Apple Speech Framework (macOS 26+)",
            isBuiltIn: true
        )
    ]

    static func modelDefinition(for modelId: String) -> ModelDefinition? {
        modelDefinitions.first { $0.id == modelId }
    }

    static func family(for modelId: String) -> ModelFamily? {
        modelDefinition(for: modelId)?.family
    }
}
