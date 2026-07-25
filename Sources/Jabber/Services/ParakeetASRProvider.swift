import FluidAudio
import Foundation
import os

final class ParakeetASRProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String
    private var streamingManager: AsrManager?
    private var finalManager: AsrManager?
    private var latestStreamingPreview: StreamingPreview?
    private let readyState = OSAllocatedUnfairLock(initialState: false)

    private struct StreamingPreview {
        let text: String
        let sampleCount: Int
        let finishedAt: ContinuousClock.Instant
    }

    init(modelId: String) {
        self.modelId = modelId
    }

    var isReady: Bool {
        readyState.withLock { $0 }
    }

    var supportsStreamingTranscription: Bool {
        true
    }

    func load(from cacheDir: URL, progressHandler: (@Sendable (Double, String) -> Void)?) async throws {
        let models = try await AsrModels.load(
            from: cacheDir,
            version: .v2,
            progressHandler: { progress in
                progressHandler?(progress.fractionCompleted, Self.status(for: progress.phase))
            }
        )
        streamingManager = AsrManager(config: .default, models: models)
        finalManager = AsrManager(config: .default, models: models)
        latestStreamingPreview = nil
        readyState.withLock { $0 = true }
    }

    func transcribe(samples: [Float], language _: String?) async throws -> String {
        guard let manager = finalManager else {
            throw TranscriptionError.loadFailed
        }
        defer { latestStreamingPreview = nil }

        if let latestStreamingPreview {
            let previewAge = ContinuousClock.now - latestStreamingPreview.finishedAt
            let tailRMS = Self.rms(
                samples: samples,
                startIndex: min(latestStreamingPreview.sampleCount, samples.count)
            )
            if Self.canReuseStreamingPreview(
                text: latestStreamingPreview.text,
                finalSampleCount: samples.count,
                previewSampleCount: latestStreamingPreview.sampleCount,
                previewAge: previewAge,
                tailRMS: tailRMS
            ) {
                return latestStreamingPreview.text
            }
        }

        let decoderLayers = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeStreaming(samples: [Float], language _: String?) async throws -> String {
        guard let manager = streamingManager else {
            throw TranscriptionError.loadFailed
        }

        let decoderLayers = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        latestStreamingPreview = StreamingPreview(
            text: text,
            sampleCount: samples.count,
            finishedAt: ContinuousClock.now
        )
        return text
    }

    func resetStreamingTranscription() {
        latestStreamingPreview = nil
    }

    func unload() {
        readyState.withLock { $0 = false }
        streamingManager = nil
        finalManager = nil
        latestStreamingPreview = nil
    }

    nonisolated static func canReuseStreamingPreview(
        text: String,
        finalSampleCount: Int,
        previewSampleCount: Int,
        previewAge: Duration,
        tailRMS: Float
    ) -> Bool {
        let boundedPreviewCount = min(previewSampleCount, finalSampleCount)
        let tailSamples = max(0, finalSampleCount - boundedPreviewCount)
        let tailDuration = Duration.seconds(Double(tailSamples) / 16_000)
        let coverage = finalSampleCount > 0
            ? Double(boundedPreviewCount) / Double(finalSampleCount)
            : 0

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard previewSampleCount > 0, finalSampleCount >= 32_000 else { return false }
        guard previewAge <= .seconds(3) else { return false }
        guard coverage >= 0.88, tailDuration <= .milliseconds(1_800) else { return false }
        return tailSamples == 0 || tailRMS <= 0.002
    }

    private static func rms(samples: [Float], startIndex: Int) -> Float {
        guard startIndex < samples.count else { return 0 }

        var sum: Float = 0
        for sample in samples[startIndex...] {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count - startIndex))
    }

    private static func status(for phase: DownloadPhase) -> String {
        switch phase {
        case .listing:
            return "Preparing Parakeet..."
        case .downloading:
            return "Loading Parakeet..."
        case .compiling(let modelName):
            return "Compiling \(modelName)..."
        }
    }
}
