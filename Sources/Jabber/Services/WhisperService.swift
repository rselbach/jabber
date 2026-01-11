import Foundation
import WhisperKit
import os

/// Thread-safe observer for WhisperService state changes.
/// Uses @unchecked Sendable because NSLock-protected mutable state cannot be verified
/// by the compiler, but manual synchronization with NSLock ensures thread safety.
final class WhisperStateObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var _isReady = false
    private var _stateCallback: (@Sendable (WhisperService.State) -> Void)?

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    func setReady(_ value: Bool) {
        lock.lock()
        _isReady = value
        lock.unlock()
    }

    func setCallback(_ callback: @escaping @Sendable (WhisperService.State) -> Void) {
        lock.lock()
        _stateCallback = callback
        lock.unlock()
    }

    func notifyState(_ state: WhisperService.State) {
        lock.lock()
        let callback = _stateCallback
        lock.unlock()
        callback?(state)
    }
}

actor WhisperService {
    private var whisperKit: WhisperKit?
    private var isLoading = false
    private var loadedModelId: String?

    /// Generation counter for invalidating in-flight model loads.
    /// Incremented by unloadModel() so that any pending loadModel() calls
    /// detect the generation mismatch and throw CancellationError instead
    /// of clobbering the new state.
    private var loadGeneration: UInt64 = 0

    nonisolated let stateObserver = WhisperStateObserver()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "WhisperService")
    private static let loadTimeout: Duration = .seconds(600)

    enum State: Sendable {
        case notReady
        case loading
        case ready
        case error(String)
    }

    nonisolated func setStateCallback(_ callback: @escaping @Sendable (State) -> Void) {
        stateObserver.setCallback(callback)
    }

    private nonisolated func notifyState(_ state: State) {
        stateObserver.notifyState(state)
    }

    nonisolated var isReady: Bool {
        stateObserver.isReady
    }

    private func setReady(_ ready: Bool) {
        stateObserver.setReady(ready)
    }

    /// Vocabulary prompt to bias transcription toward specific terms (names, jargon, etc.)
    private var vocabularyPrompt: String = ""

    /// Language for transcription ("auto" for auto-detect, or language code like "en", "es", etc.)
    private var selectedLanguage: String = Constants.defaultLanguage

    func setVocabularyPrompt(_ prompt: String) {
        let trimmed = String(prompt.prefix(500))
        vocabularyPrompt = trimmed
    }

    func setLanguage(_ language: String) {
        // Validate language code
        if language == "auto" || Constants.validLanguageCodes.contains(language) {
            selectedLanguage = language
        } else {
            // Invalid code - fall back to auto-detect and notify user
            logger.warning("Invalid language code '\(language)' - falling back to auto-detect")
            selectedLanguage = "auto"
            UserDefaults.standard.set("auto", forKey: "selectedLanguage")

            Task { @MainActor in
                NotificationService.shared.showWarning(
                    title: "Invalid Language Setting",
                    message: "The language code '\(language)' is not recognized. Auto-detect has been enabled instead."
                )
            }
        }
    }

    private func formattedVocabularyPrompt() -> String {
        " " + vocabularyPrompt
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func promptTokens(using kit: WhisperKit) -> [Int] {
        guard !vocabularyPrompt.isEmpty, let tokenizer = kit.tokenizer else { return [] }

        let formattedPrompt = formattedVocabularyPrompt()
        guard !formattedPrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        return tokenizer.encode(text: formattedPrompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }

    func ensureModelLoaded() async throws {
        let desiredModelId = UserDefaults.standard.string(forKey: "selectedModel") ?? "base"
        if whisperKit != nil, loadedModelId == desiredModelId {
            return
        }
        try await loadModel(desiredModelId: desiredModelId)
    }

    func unloadModel() async {
        loadGeneration &+= 1
        whisperKit = nil
        loadedModelId = nil
        setReady(false)
        notifyState(.notReady)
    }

    func currentModelId() async -> String? {
        loadedModelId
    }

    func transcribe(samples: [Float]) async throws -> String {
        let kit = try await getWhisperKit()

        var options = DecodingOptions()

        // Configure language based on user preference
        if selectedLanguage == "auto" {
            options.detectLanguage = true
            options.language = nil
        } else {
            options.detectLanguage = false
            options.language = selectedLanguage
        }

        let tokens = promptTokens(using: kit)
        if !tokens.isEmpty {
            options.promptTokens = tokens
        }

        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)

        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveLoadedModel(desiredModelId: String) -> Bool {
        guard whisperKit != nil else { return false }
        guard loadedModelId == desiredModelId else {
            resetLoadedModel()
            return false
        }

        setReady(true)
        notifyState(.ready)
        return true
    }

    private func resetLoadedModel() {
        whisperKit = nil
        loadedModelId = nil
        setReady(false)
        notifyState(.notReady)
    }

    /// Loads the specified model, coordinating with concurrent callers.
    ///
    /// Concurrency model:
    /// - Only one task performs the actual load at a time (guarded by `isLoading`).
    /// - Other callers wait via `waitForModelLoad()`, then either reuse the result
    ///   or start a new load if the previous one failed or loaded a different model.
    /// - `loadGeneration` invalidates in-flight loads when `unloadModel()` is called,
    ///   ensuring stale loads don't clobber newer state.
    private func loadModel(desiredModelId: String) async throws {
        while true {
            if isLoading {
                try await waitForModelLoad()
            }

            if resolveLoadedModel(desiredModelId: desiredModelId) {
                return
            }

            let currentLoadGeneration = loadGeneration
            isLoading = true
            defer { isLoading = false }

            try Task.checkCancellation()
            guard loadGeneration == currentLoadGeneration else { throw CancellationError() }

            var modelIdToLoad = desiredModelId
            let modelFolder: URL
            do {
                modelFolder = try await ModelManager.shared.ensureModelDownloaded(modelIdToLoad)
            } catch let error as ModelError {
                switch error {
                case .modelNotFound:
                    logger.warning("Unknown model id '\(modelIdToLoad)', falling back to base")
                    modelIdToLoad = "base"
                    UserDefaults.standard.set(modelIdToLoad, forKey: "selectedModel")
                    modelFolder = try await ModelManager.shared.ensureModelDownloaded(modelIdToLoad)
                default:
                    throw error
                }
            }

            try Task.checkCancellation()
            guard loadGeneration == currentLoadGeneration else { throw CancellationError() }

            notifyState(.loading)

            let kit = try await WhisperKit(modelFolder: modelFolder.path)

            try Task.checkCancellation()
            guard loadGeneration == currentLoadGeneration else { throw CancellationError() }

            whisperKit = kit
            loadedModelId = modelIdToLoad
            setReady(true)
            notifyState(.ready)
            return
        }
    }

    private func getWhisperKit() async throws -> WhisperKit {
        try await ensureModelLoaded()
        guard let kit = whisperKit else {
            throw WhisperError.loadFailed
        }
        return kit
    }

    private func waitForModelLoad() async throws {
        let startTime = ContinuousClock.now
        var backoffDelay: Duration = .milliseconds(100)
        let maxBackoff: Duration = .seconds(1)

        while isLoading {
            let elapsed = ContinuousClock.now - startTime
            if elapsed > Self.loadTimeout {
                logger.error("Timeout waiting for model to load")
                throw WhisperError.loadTimeout
            }

            try await Task.sleep(for: backoffDelay)

            // Exponential backoff with max cap
            backoffDelay = min(backoffDelay * 2, maxBackoff)
        }
    }
}

enum WhisperError: Error, LocalizedError {
    case loadFailed
    case loadTimeout
    case transcriptionFailed
    case modelNotReady

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "Failed to load the transcription model"
        case .loadTimeout:
            return "Model loading timed out"
        case .transcriptionFailed:
            return "Transcription failed"
        case .modelNotReady:
            return "Transcription model is not ready"
        }
    }
}
