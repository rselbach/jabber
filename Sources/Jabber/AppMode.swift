import Foundation

enum AppMode {
    static let qwen3ModelId = "qwen3"
    static let parakeetModelId = "parakeet"
    static let nemotronModelId = "nemotron"
    static let appleSpeechModelId = "apple-speech"

    enum ModelFamily: String, CaseIterable {
        case qwen3ASR
        case parakeetASR
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
            id: qwen3ModelId,
            family: .qwen3ASR,
            huggingFaceModelId: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit",
            name: "Qwen3-ASR",
            description: "Qwen3-ASR 1.7B 8-bit — 52 languages, highest accuracy",
            sizeHint: "~2.5GB",
            supportedLanguageCodes: nil,
            license: "Apache 2.0",
            licenseUrl: "https://www.apache.org/licenses/LICENSE-2.0",
            attribution: "Qwen3-ASR by Alibaba Qwen Team",
            isBuiltIn: false
        ),
        .init(
            id: parakeetModelId,
            family: .parakeetASR,
            huggingFaceModelId: "aufklarer/Parakeet-TDT-v3-CoreML-INT8",
            name: "Parakeet",
            description: "NVIDIA Parakeet TDT v3 — fastest, best European accuracy",
            sizeHint: "~634MB",
            supportedLanguageCodes: parakeetLanguageCodes,
            license: "CC-BY-4.0",
            licenseUrl: "https://creativecommons.org/licenses/by/4.0/",
            attribution: "Parakeet TDT v3 by NVIDIA",
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

    static let parakeetLanguageCodes: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de",
        "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk",
        "sl", "es", "sv", "ru", "uk"
    ]

    static func modelDefinition(for modelId: String) -> ModelDefinition? {
        modelDefinitions.first { $0.id == modelId }
    }

    static func family(for modelId: String) -> ModelFamily? {
        modelDefinition(for: modelId)?.family
    }

    // MARK: - Legacy Qwen3 API (used by ModelManager migration)

    struct Qwen3ASRVariant {
        let modelId: String
        let huggingFaceModelId: String
        let name: String
        let description: String
        let sizeHint: String
    }

    static let qwen3ASRVariants: [Qwen3ASRVariant] = modelDefinitions
        .filter { $0.family == .qwen3ASR }
        .map {
            .init(
                modelId: $0.id,
                huggingFaceModelId: $0.huggingFaceModelId,
                name: $0.name,
                description: $0.description,
                sizeHint: $0.sizeHint
            )
        }

    static func qwen3ASRVariant(for modelId: String) -> Qwen3ASRVariant? {
        qwen3ASRVariants.first { $0.modelId == modelId }
    }
}
