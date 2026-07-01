import Foundation

enum LanguageModelCatalog {
    struct Route: Identifiable {
        let modelId: String
        let isRecommended: Bool

        var id: String {
            modelId
        }
    }

    static let popularLanguageCodes: [String] = [
        "en", "es", "fr", "de", "pt", "it", "ja", "ko", "zh", "hi", "ar"
    ]

    static func routes(for languageCode: String) -> [Route] {
        if languageCode == "auto" {
            return [
                .init(modelId: AppMode.parakeetModelId, isRecommended: true),
                .init(modelId: AppMode.nemotronModelId, isRecommended: false),
                .init(modelId: AppMode.qwen3ModelId, isRecommended: false)
            ]
        }

        if languageCode == "en" {
            return [
                .init(modelId: AppMode.nemotronModelId, isRecommended: true),
                .init(modelId: AppMode.parakeetModelId, isRecommended: false),
                .init(modelId: AppMode.qwen3ModelId, isRecommended: false)
            ]
        }

        if AppMode.parakeetLanguageCodes.contains(languageCode) {
            return [
                .init(modelId: AppMode.parakeetModelId, isRecommended: true),
                .init(modelId: AppMode.qwen3ModelId, isRecommended: false)
            ]
        }

        return [
            .init(modelId: AppMode.qwen3ModelId, isRecommended: true)
        ]
    }

    static func recommendedModelId(for languageCode: String) -> String {
        routes(for: languageCode).first(where: { $0.isRecommended })?.modelId
            ?? AppMode.qwen3ModelId
    }

    static func compatibleModelIds(for languageCode: String) -> [String] {
        routes(for: languageCode).map(\.modelId)
    }

    static func supportsLanguage(_ languageCode: String, modelId: String) -> Bool {
        guard let def = AppMode.modelDefinition(for: modelId) else { return false }
        guard let supported = def.supportedLanguageCodes else { return true }
        if languageCode == "auto" { return true }
        return supported.contains(languageCode)
    }

    static func popularLanguages() -> [(name: String, code: String)] {
        popularLanguageCodes.compactMap { code in
            Constants.sortedLanguages.first { $0.code == code }
        }
    }

    static func allLanguages() -> [(name: String, code: String)] {
        Constants.sortedLanguages
    }
}
