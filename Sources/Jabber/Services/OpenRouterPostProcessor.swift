import Foundation
import os

/// Errors surfaced by `OpenRouterPostProcessor`. The API key is never included
/// in any of these messages or in logs.
enum OpenRouterPostProcessingError: LocalizedError, Equatable {
    /// No API key is stored / the stored key is blank.
    case missingApiKey
    /// The API returned a non-2xx status.
    case httpFailure(Int)
    /// The response JSON did not match the expected OpenAI shape.
    case malformedResponse
    /// The response parsed but contained no usable choice/message content.
    case emptyResponse
    /// The transport threw (network/URLSession error). Carries the underlying
    /// error's `localizedDescription`, never the key.
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            "OpenRouter API key is not set."
        case let .httpFailure(code):
            "OpenRouter returned HTTP \(code)."
        case .malformedResponse:
            "OpenRouter response could not be parsed."
        case .emptyResponse:
            "OpenRouter returned an empty response."
        case let .networkError(message):
            "OpenRouter request failed: \(message)"
        }
    }
}

/// OpenRouter-backed transcript refinement. Conforms to the same
/// `PostProcessingProvider` contract as the on-device Apple Intelligence
/// processor, so the coordinator's existing guardrails/retry/raw-fallback
/// behavior applies unchanged.
///
/// Request shape (OpenAI chat completions, non-streaming):
/// ```
/// POST https://openrouter.ai/api/v1/chat/completions
/// Content-Type: application/json
/// Authorization: Bearer <key>
/// X-Title: Jabber
/// HTTP-Referer: https://rselbach.github.io/jabber/
/// {
///   "model": "<slug>",
///   "messages": [
///     {"role":"system","content":"<AppleIntelligencePostProcessor.instructions>"},
///     {"role":"user","content":"<raw transcript>"}
///   ],
///   "stream": false,
///   "temperature": 0
/// }
/// ```
/// Response: `choices[0].message.content` is returned verbatim. An empty/whitespace
/// content string is a *valid* outcome (a self-correction like "scratch that"),
/// not a failure — the coordinator normalizes it and types nothing, matching the
/// Apple Intelligence contract.
///
/// Transport is injected so tests never hit the network. The default uses
/// `URLSession.shared` with a 60s timeout: transcripts are short, but a generous
/// timeout avoids spurious failures on slow/hotspot links.
struct OpenRouterPostProcessor: PostProcessingProvider {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// 60s: short transcripts normally return in a few seconds, but a generous
    /// ceiling avoids spurious timeouts on slow networks.
    static let requestTimeout: TimeInterval = 60

    let apiKey: String
    let modelId: String
    let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// - Parameters:
    ///   - apiKey: OpenRouter API key. Blank/whitespace makes `isAvailable` false.
    ///   - modelId: OpenRouter slug. Validated against the catalog; unknown slugs
    ///     fall back to the default so a stored value can never be sent unverified.
    ///   - transport: Injected transport for tests. Default uses URLSession.
    init(
        apiKey: String,
        modelId: String = OpenRouterModelCatalog.defaultModelId,
        transport: @Sendable @escaping (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.apiKey = apiKey
        self.modelId = OpenRouterModelCatalog.resolveModelId(modelId)
        self.transport = transport
    }

    var displayName: String {
        "OpenRouter"
    }

    var isAvailable: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func process(_ transcript: String) async throws -> String {
        guard isAvailable else {
            throw OpenRouterPostProcessingError.missingApiKey
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // OpenRouter attribution headers. X-Title is the app name; HTTP-Referer
        // uses the stable app/appcast URL already referenced in Info.plist/README
        // (no invented URL).
        request.setValue("Jabber", forHTTPHeaderField: "X-Title")
        request.setValue("https://rselbach.github.io/jabber/", forHTTPHeaderField: "HTTP-Referer")

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": AppleIntelligencePostProcessor.instructions],
                ["role": "user", "content": transcript]
            ],
            "stream": false,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession.data(for:) reacts to task cancellation by throwing
            // URLError(.cancelled), not CancellationError. Map it so a
            // cancelled dictation is not surfaced to the user as a spurious
            // network failure.
            throw CancellationError()
        } catch {
            throw OpenRouterPostProcessingError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterPostProcessingError.malformedResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw OpenRouterPostProcessingError.httpFailure(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenRouterPostProcessingError.malformedResponse
        }
        guard let choices = json["choices"] as? [[String: Any]], !choices.isEmpty else {
            // Parsed, but no choices to use.
            throw OpenRouterPostProcessingError.emptyResponse
        }
        guard let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            // Choices present but the message/content shape is wrong.
            throw OpenRouterPostProcessingError.malformedResponse
        }

        // Preserve the post-processing contract: return content verbatim. An
        // empty/whitespace string is a valid cancellation outcome handled by the
        // coordinator (it trims and treats empty as "type nothing").
        return content
    }
}

/// Routes post-processing to the provider selected in settings at call time.
/// Injected as the default `PostProcessingProvider` in `DictationCoordinator`
/// so the coordinator never has to be rebuilt when the user changes providers.
///
/// Reads `UserDefaults.standard` directly (thread-safe) rather than the
/// MainActor-isolated `TypedSettings` accessor, because the protocol's
/// `isAvailable` is a synchronous non-isolated requirement. Validation is
/// shared with the typed accessor via the pure `resolve` helpers.
struct RoutedPostProcessor: PostProcessingProvider {
    private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "PostProcessingRouter")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var displayName: String {
        currentKind().displayName
    }

    var isAvailable: Bool {
        switch currentKind() {
        case .appleIntelligence:
            return AppleIntelligencePostProcessor().isAvailable
        case .openRouter:
            return OpenRouterPostProcessor(apiKey: Self.currentApiKey(), modelId: currentModelId()).isAvailable
        }
    }

    func process(_ transcript: String) async throws -> String {
        switch currentKind() {
        case .appleIntelligence:
            return try await AppleIntelligencePostProcessor().process(transcript)
        case .openRouter:
            return try await OpenRouterPostProcessor(
                apiKey: Self.currentApiKey(),
                modelId: currentModelId()
            ).process(transcript)
        }
    }

    // MARK: - Call-time settings reads (non-isolated, UserDefaults is thread-safe)

    private func currentKind() -> PostProcessingProviderKind {
        PostProcessingProviderKind.resolve(
            rawValue: defaults.string(forKey: AppSettingKey.postProcessingProviderKind)
        )
    }

    private func currentModelId() -> String {
        OpenRouterModelCatalog.resolveModelId(
            defaults.string(forKey: AppSettingKey.openRouterModel)
        )
    }

    /// Reads the API key from Keychain. A keychain read failure is logged and
    /// treated as "no key" so dictation falls back to raw transcript instead of
    /// surfacing a disruptive alert; the Settings UI surfaces keychain errors
    /// inline where the user can act on them.
    private static func currentApiKey() -> String {
        do {
            return try OpenRouterKeychain.readKey() ?? ""
        } catch {
            logger.error("OpenRouter API key read failed: \(error.localizedDescription)")
            return ""
        }
    }
}
