import Foundation
import NemotronStreamingASR

final class NemotronASRProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String
    private let huggingFaceModelId: String
    private var model: NemotronStreamingASRModel?
    private var streamingSession: NemotronStreamingASR.StreamingSession?
    private var streamedSampleCount = 0
    private var latestStreamingText = ""

    init(modelId: String, huggingFaceModelId: String) {
        self.modelId = modelId
        self.huggingFaceModelId = huggingFaceModelId
    }

    var isReady: Bool {
        model != nil
    }

    func load(from cacheDir: URL, progressHandler: (@Sendable (Double, String) -> Void)?) async throws {
        // NemotronStreamingASRModel.fromPretrained exposes no cacheDir/downloadBase parameter, so
        // the protocol-supplied cacheDir is unused here. The dependency always resolves the storage
        // location itself via HuggingFaceDownloader.getCacheDirectory(for:), landing under
        // ~/Library/Caches/qwen3-speech/models/<org>/<model>/ (matching ModelManager.cacheBase()'s
        // default). If cacheBase() is overridden (custom cacheBaseURL / QWEN3_CACHE_DIR / sandboxed
        // container) Nemotron will NOT follow it and may duplicate the multi-GB download. Unlike
        // Qwen3ASRProvider, this cannot be fixed without a change in the speech-swift dependency.
        let m = try await NemotronStreamingASRModel.fromPretrained(
            modelId: huggingFaceModelId,
            progressHandler: { progress, status in
                progressHandler?(progress, status)
            }
        )
        model = m
    }

    func transcribe(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String {
        defer { resetStreamingTranscription() }

        guard let model else {
            throw TranscriptionError.loadFailed
        }

        return try model.transcribeAudio(samples, sampleRate: 16_000)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeStreaming(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String {
        guard let model else {
            throw TranscriptionError.loadFailed
        }

        if samples.count <= streamedSampleCount {
            resetStreamingTranscription()
        }

        let session: NemotronStreamingASR.StreamingSession
        if let existingSession = streamingSession {
            session = existingSession
        } else {
            session = try model.createSession()
            streamingSession = session
        }

        let delta = Array(samples.dropFirst(streamedSampleCount))
        streamedSampleCount = samples.count
        guard !delta.isEmpty else {
            return latestStreamingText
        }

        let partials = try session.pushAudio(delta)
        if let text = partials.last?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            latestStreamingText = text
        }

        return latestStreamingText
    }

    func resetStreamingTranscription() {
        streamingSession = nil
        streamedSampleCount = 0
        latestStreamingText = ""
    }

    func unload() {
        resetStreamingTranscription()
        model = nil
    }
}
