import Foundation
import os
import Qwen3ASR

final class Qwen3ASRProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String
    private let huggingFaceModelId: String
    private var model: Qwen3ASRModel?
    /// isReady is read from the TranscriptionService actor while unload() can
    /// be running on the provider-call gate; `model` itself stays confined to
    /// gate-serialized calls, so mirror readiness in a lock-guarded flag
    /// instead of racing on the unprotected var.
    private let readyState = OSAllocatedUnfairLock(initialState: false)

    init(modelId: String, huggingFaceModelId: String) {
        self.modelId = modelId
        self.huggingFaceModelId = huggingFaceModelId
    }

    var isReady: Bool {
        readyState.withLock { $0 }
    }

    func load(from cacheDir: URL, progressHandler: (@Sendable (Double, String) -> Void)?) async throws {
        let m = try await Qwen3ASRModel.fromPretrained(
            modelId: huggingFaceModelId,
            cacheDir: cacheDir,
            offlineMode: true,
            progressHandler: { progress, status in
                progressHandler?(progress, status)
            }
        )
        model = m
        readyState.withLock { $0 = true }
    }

    func transcribe(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String {
        guard let model else {
            throw TranscriptionError.loadFailed
        }

        let context = vocabularyPrompt?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let options = Qwen3DecodingOptions(
            language: language,
            context: context?.isEmpty == true ? nil : context,
            repetitionPenalty: 1.15
        )

        return model.transcribe(audio: samples, sampleRate: 16_000, options: options)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        readyState.withLock { $0 = false }
        model = nil
    }
}
