import Foundation

/// What a speech model actually does with the selected language.
enum LanguageModelCompatibility: Equatable {
    /// The model transcribes the selected language.
    case supported
    /// The model cannot transcribe the selected language; the recommended
    /// model for that language can.
    case unsupported(recommendedModelId: String)
    /// Auto-detect with a model that identifies the spoken language itself.
    case detectsLanguage
    /// Auto-detect with a single-language model, which always transcribes
    /// that language.
    case assumesLanguage(String)
    /// Auto-detect with Apple Speech, which needs a locale up front and uses
    /// the system language. Nil when the system language is unknown.
    case usesSystemLanguage(String?)
}

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
            // Apple Speech leads because it covers every language Jabber
            // offers; Parakeet v3 needs the language named to pick a script.
            return [
                .init(modelId: AppMode.appleSpeechModelId, isRecommended: true),
                .init(modelId: AppMode.parakeetMultilingualModelId, isRecommended: false),
                .init(modelId: AppMode.parakeetModelId, isRecommended: false),
                .init(modelId: AppMode.nemotronModelId, isRecommended: false),
            ]
        }

        if languageCode == "en" {
            // v2 is English-only and more accurate on it than multilingual v3.
            return [
                .init(modelId: AppMode.parakeetModelId, isRecommended: true),
                .init(modelId: AppMode.parakeetMultilingualModelId, isRecommended: false),
                .init(modelId: AppMode.nemotronModelId, isRecommended: false),
                .init(modelId: AppMode.appleSpeechModelId, isRecommended: false)
            ]
        }

        if AppMode.parakeetMultilingualLanguageCodes.contains(languageCode) {
            return [
                .init(modelId: AppMode.parakeetMultilingualModelId, isRecommended: true),
                .init(modelId: AppMode.appleSpeechModelId, isRecommended: false)
            ]
        }

        if languageCode == "ja" {
            return [
                .init(modelId: AppMode.parakeetJapaneseModelId, isRecommended: true),
                .init(modelId: AppMode.appleSpeechModelId, isRecommended: false)
            ]
        }

        return [
            .init(modelId: AppMode.appleSpeechModelId, isRecommended: true)
        ]
    }

    static func recommendedModelId(for languageCode: String) -> String {
        routes(for: languageCode).first(where: { $0.isRecommended })?.modelId
            ?? AppMode.appleSpeechModelId
    }

    static func compatibleModelIds(for languageCode: String) -> [String] {
        routes(for: languageCode).map(\.modelId)
    }

    static func supportsLanguage(_ languageCode: String, modelId: String) -> Bool {
        guard let def = AppMode.modelDefinition(for: modelId) else { return false }
        guard let supported = def.supportedLanguageCodes else { return true }
        if languageCode == "auto" {
            return true
        }
        return supported.contains(languageCode)
    }

    /// Resolves what `modelId` will actually do with `languageCode`.
    /// `systemLanguageCode` is the language Apple Speech falls back to for
    /// auto-detect; it is injected so this stays pure. Nil for unknown models.
    static func compatibility(
        languageCode: String,
        modelId: String,
        systemLanguageCode: String?
    ) -> LanguageModelCompatibility? {
        guard let def = AppMode.modelDefinition(for: modelId) else { return nil }

        guard languageCode == "auto" else {
            guard supportsLanguage(languageCode, modelId: modelId) else {
                return .unsupported(recommendedModelId: recommendedModelId(for: languageCode))
            }
            return .supported
        }

        // Only Apple Speech has no language list, and it cannot detect: it
        // needs a locale up front and takes the system's.
        guard let supported = def.supportedLanguageCodes else {
            return .usesSystemLanguage(systemLanguageCode)
        }
        if supported.count == 1, let only = supported.first {
            return .assumesLanguage(only)
        }
        return .detectsLanguage
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
