import Foundation

enum AppMode {
    static let qwen3ModelId = "qwen3"
    static let qwen3Small4BitModelId = "qwen3-0.6b-4bit"
    static let qwen3Small8BitModelId = "qwen3-0.6b-8bit"
    static let qwen3Large4BitModelId = "qwen3-1.7b-4bit"
    static let nemotronModelId = "nemotron"
    static let appleSpeechModelId = "apple-speech"

    static let qwen3ModelIds = [
        qwen3ModelId,
        qwen3Large4BitModelId,
        qwen3Small8BitModelId,
        qwen3Small4BitModelId
    ]

    enum ModelFamily: String, CaseIterable {
        case qwen3ASR
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
            name: "Qwen3-ASR 1.7B 8-bit",
            description: "Qwen3-ASR 1.7B 8-bit — 52 languages, highest accuracy",
            sizeHint: "~2.5GB",
            supportedLanguageCodes: nil,
            license: "Apache 2.0",
            licenseUrl: "https://www.apache.org/licenses/LICENSE-2.0",
            attribution: "Qwen3-ASR by Alibaba Qwen Team",
            isBuiltIn: false
        ),
        .init(
            id: qwen3Large4BitModelId,
            family: .qwen3ASR,
            huggingFaceModelId: "aufklarer/Qwen3-ASR-1.7B-MLX-4bit",
            name: "Qwen3-ASR 1.7B 4-bit",
            description: "Qwen3-ASR 1.7B 4-bit — 52 languages, smaller 1.7B download",
            sizeHint: "~1.3GB",
            supportedLanguageCodes: nil,
            license: "Apache 2.0",
            licenseUrl: "https://www.apache.org/licenses/LICENSE-2.0",
            attribution: "Qwen3-ASR by Alibaba Qwen Team",
            isBuiltIn: false
        ),
        .init(
            id: qwen3Small8BitModelId,
            family: .qwen3ASR,
            huggingFaceModelId: "aufklarer/Qwen3-ASR-0.6B-MLX-8bit",
            name: "Qwen3-ASR 0.6B 8-bit",
            description: "Qwen3-ASR 0.6B 8-bit — 52 languages, smaller model",
            sizeHint: "~1GB",
            supportedLanguageCodes: nil,
            license: "Apache 2.0",
            licenseUrl: "https://www.apache.org/licenses/LICENSE-2.0",
            attribution: "Qwen3-ASR by Alibaba Qwen Team",
            isBuiltIn: false
        ),
        .init(
            id: qwen3Small4BitModelId,
            family: .qwen3ASR,
            huggingFaceModelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit",
            name: "Qwen3-ASR 0.6B 4-bit",
            description: "Qwen3-ASR 0.6B 4-bit — 52 languages, smallest Qwen option",
            sizeHint: "~600MB",
            supportedLanguageCodes: nil,
            license: "Apache 2.0",
            licenseUrl: "https://www.apache.org/licenses/LICENSE-2.0",
            attribution: "Qwen3-ASR by Alibaba Qwen Team",
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
