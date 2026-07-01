import Foundation
import ParakeetASR

final class ParakeetASRProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String
    private let huggingFaceModelId: String
    private var model: ParakeetASRModel?

    init(modelId: String, huggingFaceModelId: String) {
        self.modelId = modelId
        self.huggingFaceModelId = huggingFaceModelId
    }

    var isReady: Bool {
        model != nil
    }

    func load(from cacheDir: URL, progressHandler: ((Double, String) -> Void)?) async throws {
        let m = try await ParakeetASRModel.fromPretrained(
            modelId: huggingFaceModelId,
            cacheDir: cacheDir,
            offlineMode: true,
            progressHandler: { progress, status in
                progressHandler?(progress, status)
            }
        )
        model = m
    }

    func transcribe(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String {
        guard let model else {
            throw TranscriptionError.loadFailed
        }

        return try model.transcribeAudio(samples, sampleRate: 16_000)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        model = nil
    }
}
