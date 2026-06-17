import Foundation

enum AppMode {
    static let baseModelId = "base"
    static let mediumModelId = "medium"
    static let largeModelId = "large"

    struct Qwen3ASRVariant {
        let modelId: String
        let huggingFaceModelId: String
        let name: String
        let description: String
        let sizeHint: String
    }

    static let qwen3ASRVariants: [Qwen3ASRVariant] = [
        .init(
            modelId: baseModelId,
            huggingFaceModelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit",
            name: "Base",
            description: "Fast, accurate Qwen3-ASR 0.6B 4-bit",
            sizeHint: "~700MB"
        ),
        .init(
            modelId: mediumModelId,
            huggingFaceModelId: "mlx-community/Qwen3-ASR-1.7B-4bit",
            name: "Medium",
            description: "Larger Qwen3-ASR 1.7B 4-bit",
            sizeHint: "~1.6GB"
        ),
        .init(
            modelId: largeModelId,
            huggingFaceModelId: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit",
            name: "Large",
            description: "Highest precision Qwen3-ASR 1.7B 8-bit",
            sizeHint: "~2.5GB"
        )
    ]

    static func qwen3ASRVariant(for modelId: String) -> Qwen3ASRVariant? {
        qwen3ASRVariants.first { $0.modelId == modelId }
    }
}
