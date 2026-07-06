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

actor ProviderCallGate {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let predecessor = tail
        let operationTask = Task.detached { () throws -> T in
            if let predecessor {
                await predecessor.value
            }
            return try await operation()
        }
        tail = Task.detached {
            // The caller awaiting operationTask receives the real result; the
            // tail only keeps later provider calls ordered.
            _ = await operationTask.result
        }
        return try await operationTask.value
    }
}

actor TranscriptionService {
    struct LoadDependencies: Sendable {
        let waitForUIReady: @Sendable () async -> Void
        let selectedModelId: @Sendable () async -> String
        let setSelectedModelId: @Sendable (String) async -> Void
        let ensureModelDownloaded: @Sendable (String) async throws -> URL
        let makeProvider: @Sendable (String) -> TranscriptionProvider?

        static let live = LoadDependencies(
            waitForUIReady: {
                await AppReadinessGate.shared.waitForUIReady()
            },
            selectedModelId: {
                await ModelManager.shared.selectedModelId()
            },
            setSelectedModelId: { modelId in
                await MainActor.run {
                    TypedSettings[.selectedModel] = modelId
                }
            },
            ensureModelDownloaded: { modelId in
                try await ModelManager.shared.ensureModelDownloaded(modelId)
            },
            makeProvider: { modelId in
                Self.defaultProvider(for: modelId)
            }
        )

        private static func defaultProvider(for modelId: String) -> TranscriptionProvider? {
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
    }

    private var provider: TranscriptionProvider?
    // All provider-touching calls (transcribe, transcribeStreaming, reset,
    // unload) route through a single gate. The providers are
    // `@unchecked Sendable` with mutable model/streaming state and no internal
    // synchronization, so a streaming preview call running concurrently with a
    // final transcribe (or an unload) would race on that state. One gate
    // serializes them; do not split it back into per-method gates.
    private let providerCallGate = ProviderCallGate()
    private let loadDependencies: LoadDependencies
    private var isLoading = false
    private var loadedModelId: String?
    private var sessionModelIdOverride: String?

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

    init(loadDependencies: LoadDependencies = .live) {
        self.loadDependencies = loadDependencies
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
        await loadDependencies.waitForUIReady()
        try Task.checkCancellation()

        let desiredModelId = await desiredModelId()
        if loadedModelId == desiredModelId,
           provider?.isReady == true {
            return
        }
        try await loadModel(desiredModelId: desiredModelId)
    }

    func unloadModel() async {
        loadGeneration &+= 1
        if let provider {
            await unloadProvider(provider)
        }
        provider = nil
        loadedModelId = nil
        setReady(false)
        notifyState(.notReady)
    }

    func setSessionModelOverride(_ modelId: String?) {
        sessionModelIdOverride = modelId
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
        let text = try await providerCallGate.run {
            try await provider.transcribe(samples: samples, language: lang, vocabularyPrompt: prompt)
        }
        try Task.checkCancellation()
        return text
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
        let text = try await providerCallGate.run {
            try await provider.transcribeStreaming(samples: samples, language: lang, vocabularyPrompt: prompt)
        }
        try Task.checkCancellation()
        return text
    }

    func resetStreamingTranscription() async {
        guard let provider else { return }
        do {
            try await providerCallGate.run {
                provider.resetStreamingTranscription()
            }
        } catch is CancellationError {
        } catch {
            logger.error("Streaming transcription reset failed: \(error.localizedDescription)")
        }
    }

    private func resolveLoadedModel(desiredModelId: String) async -> Bool {
        guard let provider, provider.isReady else { return false }
        guard loadedModelId == desiredModelId else {
            await resetLoadedModel()
            return false
        }

        setReady(true)
        notifyState(.ready)
        return true
    }

    private func resetLoadedModel() async {
        if let provider {
            await unloadProvider(provider)
        }
        provider = nil
        loadedModelId = nil
        setReady(false)
        notifyState(.notReady)
    }

    private func loadModel(desiredModelId capturedModelId: String) async throws {
        // The captured id may be stale by the time we wake from waitForModelLoad
        // (the user or a migration could have changed the selection). Re-read
        // before claiming the load so queued callers converge on the current
        // selection instead of unloading a model that was just loaded for the
        // new selection.
        var desiredModelId = capturedModelId

        while true {
            while isLoading {
                try await waitForModelLoad()
            }

            desiredModelId = await self.desiredModelId()

            if isLoading {
                continue
            }

            if await resolveLoadedModel(desiredModelId: desiredModelId) {
                return
            }

            isLoading = true
            break
        }

        let currentLoadGeneration = loadGeneration
        defer { isLoading = false }

        do {
            try Task.checkCancellation()
            guard loadGeneration == currentLoadGeneration else { throw CancellationError() }

            notifyState(.loading(status: "Preparing model...", progress: nil))

            var modelIdToLoad = desiredModelId
            let modelFolder: URL
            do {
                modelFolder = try await loadDependencies.ensureModelDownloaded(modelIdToLoad)
            } catch let error as ModelError {
                switch error {
                case .modelNotFound:
                    logger.warning("Unknown model id '\(modelIdToLoad)', falling back to base")
                    let fallbackModelId = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
                    await loadDependencies.setSelectedModelId(fallbackModelId)
                    modelIdToLoad = fallbackModelId
                    modelFolder = try await loadDependencies.ensureModelDownloaded(modelIdToLoad)
                default:
                    throw error
                }
            }

            try Task.checkCancellation()
            guard loadGeneration == currentLoadGeneration else { throw CancellationError() }

            guard let newProvider = loadDependencies.makeProvider(modelIdToLoad) else {
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
                await unloadProvider(newProvider)
                throw CancellationError()
            }
            guard loadGeneration == currentLoadGeneration else {
                await unloadProvider(newProvider)
                throw CancellationError()
            }

            if let provider {
                await unloadProvider(provider)
            }
            provider = newProvider
            loadedModelId = modelIdToLoad
            setReady(true)
            notifyState(.ready)
        } catch {
            // Surface the failure so a lazy load triggered from
            // transcribe()/transcribeStreaming() doesn't leave the menu bar
            // stuck on "Loading model..." forever. A CancellationError with
            // a matching generation is a direct cancel (e.g. app terminate)
            // and reports notReady rather than a scary error. A stale load
            // (generation bumped by a newer one) must keep quiet so it
            // doesn't clobber the newer load's .loading state.
            if loadGeneration == currentLoadGeneration {
                setReady(false)
                if error is CancellationError {
                    notifyState(.notReady)
                } else {
                    notifyState(.error(error.localizedDescription))
                }
            }
            throw error
        }
    }

    private func publishModelLoadProgress(status: String, progress: Double, generation: UInt64) {
        guard isLoading, loadGeneration == generation else { return }

        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayStatus = trimmedStatus.isEmpty ? "Loading model..." : trimmedStatus
        let boundedProgress = min(max(progress, 0), 1)
        notifyState(.loading(status: displayStatus, progress: boundedProgress))
    }

    private func unloadProvider(_ provider: TranscriptionProvider) async {
        do {
            try await providerCallGate.run {
                provider.unload()
            }
        } catch is CancellationError {
        } catch {
            logger.error("Provider unload failed: \(error.localizedDescription)")
        }
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

    private func desiredModelId() async -> String {
        if let sessionModelIdOverride {
            return sessionModelIdOverride
        }
        return await loadDependencies.selectedModelId()
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
