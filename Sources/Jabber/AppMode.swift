import Foundation

enum AppMode {
    static let parakeetModelId = "parakeet-tdt-v2"
    static let nemotronModelId = "nemotron"
    static let appleSpeechModelId = "apple-speech"

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
