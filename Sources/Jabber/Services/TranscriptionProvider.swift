import Foundation

protocol TranscriptionProvider: AnyObject, Sendable {
    var modelId: String { get }
    var isReady: Bool { get }

    func load(from cacheDir: URL, progressHandler: ((Double, String) -> Void)?) async throws
    func transcribe(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String
    func transcribeStreaming(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String
    func unload()
}

extension TranscriptionProvider {
    func transcribeStreaming(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String {
        try await transcribe(samples: samples, language: language, vocabularyPrompt: vocabularyPrompt)
    }
}
