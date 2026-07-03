import Foundation

/// Which post-processing/refinement provider Jabber uses after transcription.
/// Stored as a typed string setting (see `TypedSetting.postProcessingProviderKind`).
enum PostProcessingProviderKind: String, CaseIterable, Sendable, Identifiable {
    case appleIntelligence
    case openRouter

    /// Default provider: on-device Apple Intelligence.
    static let defaultValue: PostProcessingProviderKind = .appleIntelligence

    var id: String {
        rawValue
    }

    /// User-facing name. Used in provider-aware messages and the Settings picker.
    var displayName: String {
        switch self {
        case .appleIntelligence:
            "Apple Intelligence"
        case .openRouter:
            "OpenRouter"
        }
    }

    /// Resolves a stored raw value (possibly nil/invalid) to a valid kind.
    /// Pure function so both the MainActor settings accessor and the non-isolated
    /// provider router can share one source of truth for validation.
    static func resolve(rawValue: String?) -> PostProcessingProviderKind {
        guard let raw = rawValue, let kind = PostProcessingProviderKind(rawValue: raw) else {
            return .defaultValue
        }
        return kind
    }
}

/// Static, curated list of OpenRouter models offered in v1. Intentionally NOT
/// fetched dynamically from `/models` and NOT user-editable as free text, so the
/// picker only ever offers known-good slugs.
enum OpenRouterModelCatalog {
    struct Model: Identifiable, Sendable, Equatable {
        /// OpenRouter model slug sent verbatim in the API request `model` field.
        let id: String
        /// Label shown in the Settings picker.
        let displayName: String
    }

    /// The three curated v1 models, in display order. The default is first.
    static let models: [Model] = [
        .init(id: "~openai/gpt-mini-latest", displayName: "GPT Mini (latest)"),
        .init(id: "~anthropic/claude-haiku-latest", displayName: "Claude Haiku (latest)"),
        .init(id: "google/gemini-3.1-flash-lite", displayName: "Gemini Flash Lite")
    ]

    /// Default model slug. Also the default for the `openRouterModel` setting.
    static let defaultModelId = "~openai/gpt-mini-latest"

    /// The default model entry.
    static var defaultModel: Model {
        models.first { $0.id == defaultModelId } ?? models[0]
    }

    /// Looks up a model by slug.
    static func model(forId id: String) -> Model? {
        models.first { $0.id == id }
    }

    /// Resolves a stored raw value (possibly nil/unknown after an app update
    /// that removed a slug from the catalog) to a valid model id, falling back
    /// to the default. Pure function shared by the settings accessor and the
    /// non-isolated provider router.
    static func resolveModelId(_ raw: String?) -> String {
        guard let raw, model(forId: raw) != nil else {
            return defaultModelId
        }
        return raw
    }
}
