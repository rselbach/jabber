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
                .init(modelId: AppMode.nemotronModelId, isRecommended: true),
                .init(modelId: AppMode.appleSpeechModelId, isRecommended: false)
            ] + qwen3Routes()
        }

        if languageCode == "en" {
            return [
                .init(modelId: AppMode.nemotronModelId, isRecommended: true),
                .init(modelId: AppMode.appleSpeechModelId, isRecommended: false)
            ] + qwen3Routes()
        }

        return qwen3Routes(recommendedModelId: AppMode.qwen3ModelId) + [
            .init(modelId: AppMode.appleSpeechModelId, isRecommended: false)
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

    private static func qwen3Routes(recommendedModelId: String? = nil) -> [Route] {
        AppMode.qwen3ModelIds.map {
            .init(modelId: $0, isRecommended: $0 == recommendedModelId)
        }
    }
}
