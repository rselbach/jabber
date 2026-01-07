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
    nonisolated let stateObserver = WhisperStateObserver()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "WhisperService")
    private static let loadTimeout: Duration = .seconds(60)

    enum State: Sendable {
        case notReady
        case downloading(progress: Double, status: String)
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

    func setVocabularyPrompt(_ prompt: String) {
        let trimmed = String(prompt.prefix(500))
        vocabularyPrompt = trimmed
    }

    func ensureModelLoaded() async throws {
        if whisperKit != nil { return }
        try await loadModel()
    }

    func unloadModel() async {
        whisperKit = nil
        setReady(false)
        notifyState(.notReady)
    }

    func currentModelId() async -> String? {
        guard whisperKit != nil else { return nil }
        return UserDefaults.standard.string(forKey: "selectedModel")
    }

    func transcribe(samples: [Float]) async throws -> String {
        let kit = try await getWhisperKit()

        var options = DecodingOptions()
        options.language = "en"  // Force English since we're using multilingual model

        if !vocabularyPrompt.isEmpty, let tokenizer = kit.tokenizer {
            let tokens = tokenizer.encode(text: vocabularyPrompt).filter { $0 < 51865 }
            if !tokens.isEmpty {
                options.promptTokens = tokens
            }
        }

        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)

        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadModel() async throws {
        guard !isLoading else {
            // Another task is loading; wait until complete or timeout
            try await waitForModelLoad()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "base"

        let modelFolder: URL
        if let existingFolder = Constants.ModelPaths.localModelFolder(for: selectedModel) {
            modelFolder = existingFolder
        } else {
            modelFolder = try await WhisperKit.download(
                variant: selectedModel,
                progressCallback: { [weak self] progress in
                    let pct = progress.fractionCompleted
                    Task { @MainActor in
                        self?.notifyState(.downloading(progress: pct, status: "Downloading \(selectedModel)... \(Int(pct * 100))%"))
                    }
                }
            )
        }

        notifyState(.loading)

        let kit = try await WhisperKit(modelFolder: modelFolder.path)

        whisperKit = kit
        setReady(true)
        notifyState(.ready)
    }

    private func getWhisperKit() async throws -> WhisperKit {
        if let kit = whisperKit {
            return kit
        }
        try await loadModel()
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

        guard whisperKit != nil else {
            logger.error("Model load completed but whisperKit is nil")
            throw WhisperError.loadFailed
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
