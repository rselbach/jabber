import Foundation
import os

final class TranscriptionStateObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var _isReady = false
    private var _stateCallback: (@Sendable (TranscriptionService.State) -> Void)?

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

    func setCallback(_ callback: @escaping @Sendable (TranscriptionService.State) -> Void) {
        lock.lock()
        _stateCallback = callback
        lock.unlock()
    }

    func notifyState(_ state: TranscriptionService.State) {
        lock.lock()
        let callback = _stateCallback
        lock.unlock()
        callback?(state)
    }
}

actor TranscriptionService {
    private var provider: TranscriptionProvider?
    private var isLoading = false
    private var loadedModelId: String?

    private var loadGeneration: UInt64 = 0

    nonisolated let stateObserver = TranscriptionStateObserver()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "TranscriptionService")
    private static let loadTimeout: Duration = .seconds(600)

    enum State: Sendable {
        case notReady
        case loading(status: String, progress: Double?)
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

    nonisolated var supportsStreamingTranscription: Bool {
        true
    }

    private func setReady(_ ready: Bool) {
        stateObserver.setReady(ready)
    }

    private var vocabularyPrompt: String = ""
    private var selectedLanguage: String = Constants.defaultLanguage

    func setVocabularyPrompt(_ prompt: String) {
        vocabularyPrompt = Self.truncateVocabularyPrompt(prompt)
    }

    func setLanguage(_ language: String) {
        let resolved = Self.resolveLanguage(language)
        selectedLanguage = resolved
        if resolved != language {
            logger.warning("Invalid language code '\(language)' - falling back to auto-detect")

            Task { @MainActor in
                TypedSettings[.selectedLanguage] = "auto"
                NotificationService.shared.showWarning(
                    title: "Invalid Language Setting",
                    message: "The language code '\(language)' is not recognized. Auto-detect has been enabled instead."
                )
            }
        }
    }

    func ensureModelLoaded() async throws {
        await AppReadinessGate.shared.waitForUIReady()
        try Task.checkCancellation()

        let desiredModelId = await ModelManager.shared.selectedModelId()
        if loadedModelId == desiredModelId,
           provider?.isReady == true {
            return
        }
        try await loadModel(desiredModelId: desiredModelId)
    }

    func unloadModel() async {
        loadGeneration &+= 1
        provider?.unload()
        provider = nil
        loadedModelId = nil
        setReady(false)
        notifyState(.notReady)
    }

    func currentModelId() async -> String? {
        loadedModelId
    }

    func transcribe(samples: [Float]) async throws -> String {
        try Task.checkCancellation()

        try await ensureModelLoaded()

        try Task.checkCancellation()

        guard let provider else {
            throw TranscriptionError.loadFailed
        }

        let lang = Self.resolveLanguageForProvider(selectedLanguage)
        let prompt = vocabularyPrompt.isEmpty ? nil : vocabularyPrompt
        return try await provider.transcribe(samples: samples, language: lang, vocabularyPrompt: prompt)
    }

    func transcribeStreaming(samples: [Float]) async throws -> String {
        try Task.checkCancellation()

        try await ensureModelLoaded()

        try Task.checkCancellation()

        guard let provider else {
            throw TranscriptionError.loadFailed
        }

        let lang = Self.resolveLanguageForProvider(selectedLanguage)
        let prompt = vocabularyPrompt.isEmpty ? nil : vocabularyPrompt
        return try await provider.transcribeStreaming(samples: samples, language: lang, vocabularyPrompt: prompt)
    }

    func resetStreamingTranscription() {
        provider?.resetStreamingTranscription()
    }

    private func resolveLoadedModel(desiredModelId: String) -> Bool {
        guard let provider, provider.isReady else { return false }
        guard loadedModelId == desiredModelId else {
            resetLoadedModel()
            return false
        }

        setReady(true)
        notifyState(.ready)
        return true
    }

    private func resetLoadedModel() {
        provider?.unload()
        provider = nil
        loadedModelId = nil
        setReady(false)
        notifyState(.notReady)
    }

    private func makeProvider(for modelId: String) -> TranscriptionProvider? {
        guard let def = AppMode.modelDefinition(for: modelId) else { return nil }

        switch def.family {
        case .qwen3ASR:
            return Qwen3ASRProvider(modelId: modelId, huggingFaceModelId: def.huggingFaceModelId)
        case .nemotronASR:
            return NemotronASRProvider(modelId: modelId, huggingFaceModelId: def.huggingFaceModelId)
        case .appleSpeech:
            return AppleSpeechProvider(modelId: modelId)
        }
    }

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

            notifyState(.loading(status: "Preparing model...", progress: nil))

            var modelIdToLoad = desiredModelId
            let modelFolder: URL
            do {
                modelFolder = try await ModelManager.shared.ensureModelDownloaded(modelIdToLoad)
            } catch let error as ModelError {
                switch error {
                case .modelNotFound:
                    logger.warning("Unknown model id '\(modelIdToLoad)', falling back to base")
                    let fallbackModelId = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
                    await MainActor.run {
                        TypedSettings[.selectedModel] = fallbackModelId
                    }
                    modelIdToLoad = fallbackModelId
                    modelFolder = try await ModelManager.shared.ensureModelDownloaded(modelIdToLoad)
                default:
                    throw error
                }
            }

            try Task.checkCancellation()
            guard loadGeneration == currentLoadGeneration else { throw CancellationError() }

            guard let newProvider = makeProvider(for: modelIdToLoad) else {
                throw ModelError.modelNotFound(modelId: modelIdToLoad)
            }

            notifyState(.loading(status: "Loading model...", progress: nil))

            try await newProvider.load(from: modelFolder) { [weak self] progress, status in
                Task {
                    await self?.publishModelLoadProgress(
                        status: status,
                        progress: progress,
                        generation: currentLoadGeneration
                    )
                }
            }

            // Both bail-out paths after a successful load must release the
            // freshly-loaded weights. `newProvider.load(from:)` brought multi-GB
            // MLX buffers into memory; discarding the reference without
            // unloading leaks them until the next load replaces the provider.
            if Task.isCancelled {
                newProvider.unload()
                throw CancellationError()
            }
            guard loadGeneration == currentLoadGeneration else {
                newProvider.unload()
                throw CancellationError()
            }

            provider = newProvider
            loadedModelId = modelIdToLoad
            setReady(true)
            notifyState(.ready)
            return
        }
    }

    private func publishModelLoadProgress(status: String, progress: Double, generation: UInt64) {
        guard isLoading, loadGeneration == generation else { return }

        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayStatus = trimmedStatus.isEmpty ? "Loading model..." : trimmedStatus
        let boundedProgress = min(max(progress, 0), 1)
        notifyState(.loading(status: displayStatus, progress: boundedProgress))
    }

    private func waitForModelLoad() async throws {
        let startTime = ContinuousClock.now
        var backoffDelay: Duration = .milliseconds(100)
        let maxBackoff: Duration = .seconds(1)

        while isLoading {
            let elapsed = ContinuousClock.now - startTime
            if elapsed > Self.loadTimeout {
                logger.error("Timeout waiting for model to load")
                throw TranscriptionError.loadTimeout
            }

            try await Task.sleep(for: backoffDelay)

            backoffDelay = min(backoffDelay * 2, maxBackoff)
        }
    }

    // MARK: - Pure resolution helpers (testable without the actor)

    /// Returns the language code if valid, otherwise "auto". Valid codes are
    /// "auto" and any code in `Constants.validLanguageCodes`.
    nonisolated static func resolveLanguage(_ code: String) -> String {
        code == "auto" || Constants.validLanguageCodes.contains(code) ? code : "auto"
    }

    /// Returns nil for "auto" (provider auto-detects), otherwise the code.
    nonisolated static func resolveLanguageForProvider(_ code: String) -> String? {
        code == "auto" ? nil : code
    }

    /// Truncates the vocabulary prompt to the maximum length the ASR model
    /// accepts as context.
    nonisolated static func truncateVocabularyPrompt(_ prompt: String) -> String {
        String(prompt.prefix(500))
    }
}

enum TranscriptionError: Error, LocalizedError {
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
