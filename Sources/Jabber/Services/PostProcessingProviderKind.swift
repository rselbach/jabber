import Foundation

/// Which post-processing/refinement provider Jabber uses after transcription.
/// Stored as a typed string setting (see `TypedSetting.postProcessingProviderKind`).
enum PostProcessingProviderKind: String, CaseIterable, Sendable, Identifiable {
    case appleIntelligence
    case openRouter
    case openCodeZen

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
        case .openCodeZen:
            "OpenCode Zen"
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

/// How much reasoning a cleanup request asks for. Cleanup rewrites what the
/// user said rather than solving a problem, and every second a model spends
/// thinking is a second the user waits for their text, so each catalog entry
/// asks for the least reasoning its model accepts.
enum ReasoningEffort: String, Sendable {
    /// Reasoning disabled.
    case off = "none"
    case low
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
        /// Sent as `reasoning.effort`. Must be one of the efforts OpenRouter's
        /// `/models` metadata lists for the slug: a model whose reasoning is
        /// mandatory rejects `none`.
        let reasoningEffort: ReasoningEffort
    }

    /// The three curated v1 models, in display order. The default is first.
    /// The OpenAI and Anthropic slots are `~vendor/<tier>-latest` aliases that
    /// follow each vendor's small model. Google's slot is pinned: Flash-Lite has
    /// no alias, and the Flash alias resolves to a model whose reasoning cannot
    /// be turned off.
    static let models: [Model] = [
        .init(id: "~openai/gpt-luna-latest", displayName: "GPT Luna (latest)", reasoningEffort: .off),
        .init(id: "~anthropic/claude-haiku-latest", displayName: "Claude Haiku (latest)", reasoningEffort: .off),
        .init(id: "google/gemini-3.1-flash-lite", displayName: "Gemini Flash Lite", reasoningEffort: .off)
    ]

    /// Slugs an earlier release offered, mapped to the entry that replaced
    /// them, so an update keeps the user's vendor instead of resetting it.
    private static let replacedModelIds = [
        "~google/gemini-flash-latest": "google/gemini-3.1-flash-lite"
    ]

    /// Default model slug. Also the default for the `openRouterModel` setting.
    static let defaultModelId = "~openai/gpt-luna-latest"

    /// The default model entry.
    static var defaultModel: Model {
        models.first { $0.id == defaultModelId } ?? models[0]
    }

    /// Looks up a model by slug.
    static func model(forId id: String) -> Model? {
        models.first { $0.id == id }
    }

    /// Resolves a stored raw value (possibly nil, replaced, or unknown after
    /// an app update) to a catalog entry, falling back to the default. Pure
    /// function shared by the settings accessor and the non-isolated provider
    /// router.
    static func resolveModel(_ raw: String?) -> Model {
        guard let raw else { return defaultModel }
        return model(forId: replacedModelIds[raw] ?? raw) ?? defaultModel
    }

    static func resolveModelId(_ raw: String?) -> String {
        resolveModel(raw).id
    }
}

/// Curated OpenCode Zen models whose native API is Chat Completions, the only
/// protocol this client speaks. Console's harness docs say it translates
/// requests for every other model, but its API reference says each model is
/// served by one API family, so the GPT, Claude, and Gemini models stay out
/// until that is verified. Free models are intentionally excluded because Zen
/// marks them as temporary and may use submitted data for model improvement;
/// dictated transcripts can contain sensitive information. Zen has no version
/// aliases, so these slugs need refreshing when a vendor ships a successor or
/// Zen deprecates one.
enum OpenCodeZenModelCatalog {
    struct Model: Identifiable, Sendable, Equatable {
        let id: String
        let displayName: String
        /// Sent as `reasoning_effort`, the field OpenCode's own client uses on
        /// this endpoint, and limited to the efforts Zen's `/models` metadata
        /// lists. Nil for models that document only an on/off toggle, whose
        /// request field Zen does not document.
        let reasoningEffort: ReasoningEffort?
    }

    static let models: [Model] = [
        .init(id: "deepseek-v4.1-flash", displayName: "DeepSeek V4.1 Flash", reasoningEffort: .low),
        .init(id: "minimax-m3", displayName: "MiniMax M3", reasoningEffort: nil),
        .init(id: "mistral-large-4", displayName: "Mistral Large 4", reasoningEffort: .off)
    ]

    static let defaultModelId = "deepseek-v4.1-flash"

    static var defaultModel: Model {
        models.first { $0.id == defaultModelId } ?? models[0]
    }

    static func model(forId id: String) -> Model? {
        models.first { $0.id == id }
    }

    static func resolveModel(_ raw: String?) -> Model {
        guard let raw else { return defaultModel }
        return model(forId: raw) ?? defaultModel
    }

    static func resolveModelId(_ raw: String?) -> String {
        resolveModel(raw).id
    }
}
