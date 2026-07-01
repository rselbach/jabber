import Foundation
import Qwen3ASR

final class Qwen3ASRProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String
    private let huggingFaceModelId: String
    private var model: Qwen3ASRModel?

    init(modelId: String, huggingFaceModelId: String) {
        self.modelId = modelId
        self.huggingFaceModelId = huggingFaceModelId
    }

    var isReady: Bool {
        model != nil
    }

    func load(from cacheDir: URL, progressHandler: ((Double, String) -> Void)?) async throws {
        let m = try await Qwen3ASRModel.fromPretrained(
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
        model = nil
    }
}
