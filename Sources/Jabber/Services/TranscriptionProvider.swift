import Foundation

protocol TranscriptionProvider: AnyObject, Sendable {
    var modelId: String { get }
    var isReady: Bool { get }
    var supportsStreamingTranscription: Bool { get }

    func load(from cacheDir: URL, progressHandler: (@Sendable (Double, String) -> Void)?) async throws
    func transcribe(samples: [Float], language: String?) async throws -> String
    func transcribeStreaming(samples: [Float], language: String?) async throws -> String
    func resetStreamingTranscription()
    func unload()
}

extension TranscriptionProvider {
    var supportsStreamingTranscription: Bool {
        false
    }

    func transcribeStreaming(samples: [Float], language: String?) async throws -> String {
        try await transcribe(samples: samples, language: language)
    }

    func resetStreamingTranscription() {}
}
