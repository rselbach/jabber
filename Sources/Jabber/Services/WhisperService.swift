import Foundation
import WhisperKit
import os

actor WhisperService {
    private var whisperKit: WhisperKit?
    private var isLoading = false
    private nonisolated(unsafe) var _isReady = false
    private let stateLock = NSLock()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "WhisperService")
    private static let loadTimeout: Duration = .seconds(60)

    enum State: Sendable {
        case notReady
        case downloading(progress: Double, status: String)
        case loading
        case ready
        case error(String)
    }

    private nonisolated(unsafe) var _stateCallback: (@Sendable (State) -> Void)?

    nonisolated func setStateCallback(_ callback: @escaping @Sendable (State) -> Void) {
        stateLock.lock()
        _stateCallback = callback
        stateLock.unlock()
    }

    private nonisolated func notifyState(_ state: State) {
        stateLock.lock()
        let callback = _stateCallback
        stateLock.unlock()
        callback?(state)
    }

    nonisolated var isReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isReady
    }

    private func setReady(_ ready: Bool) {
        stateLock.lock()
        _isReady = ready
        stateLock.unlock()
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
            // Wait for current load to complete with timeout
            let startTime = ContinuousClock.now
            while isLoading {
                let elapsed = ContinuousClock.now - startTime
                if elapsed > Self.loadTimeout {
                    logger.error("Timeout waiting for model to load")
                    throw WhisperError.loadTimeout
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard whisperKit != nil else {
                throw WhisperError.loadFailed
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "base"

        let modelFolder: URL
        if let existingFolder = localModelFolder(for: selectedModel) {
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

    private nonisolated func localModelFolder(for modelId: String) -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let base = docs
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc/whisperkit-coreml")

        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return nil }

        guard let contents = try? fm.contentsOfDirectory(atPath: base.path) else { return nil }

        // Match folders ending with "-{modelId}" to avoid false matches
        // e.g., "openai_whisper-base" or "base" but not "base-small"
        let suffixPattern = "-\(modelId)"

        for folder in contents {
            let matchesExactSuffix = folder.hasSuffix(suffixPattern)
            let matchesExactName = folder == modelId

            guard matchesExactSuffix || matchesExactName else {
                continue
            }

            let folderURL = base.appendingPathComponent(folder)
            let configPath = folderURL.appendingPathComponent("config.json")

            guard fm.fileExists(atPath: configPath.path) else {
                continue
            }

            return folderURL
        }
        return nil
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
