@preconcurrency import AVFAudio
import FluidAudio
import Foundation
import os

/// NVIDIA Parakeet Unified through FluidAudio's streaming manager. The
/// Parakeet TDT providers re-transcribe the whole recording for every
/// preview; this one decodes each chunk of new audio once, so a preview costs
/// only the audio since the last one and the final transcript only flushes
/// the tail.
final class UnifiedASRProvider: TranscriptionProvider, @unchecked Sendable {
    /// 5.6 s of left context, then 0.56 s chunks with 0.56 s of look-ahead,
    /// so the live preview trails speech by about a second. Against the
    /// 0.32 s tier this makes about a fifth fewer errors on hard LibriSpeech
    /// audio and needs a quarter of the compute. The context is baked into
    /// each encoder export, so this also picks the encoder the model
    /// download fetches.
    static let config = UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7)

    let modelId: String
    private var manager: StreamingUnifiedAsrManager?
    /// Samples of the current recording the manager has been given, or nil
    /// when its session must be reset before it takes more.
    private var streamedSampleCount: Int?
    /// isReady is read from the TranscriptionService actor while unload() can
    /// be running on the provider-call gate, so readiness is mirrored in a
    /// lock-guarded flag; `manager` itself stays confined to gate-serialized
    /// calls.
    private let readyState = OSAllocatedUnfairLock(initialState: false)

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
        progressHandler?(0, "Loading Parakeet Unified...")
        let manager = StreamingUnifiedAsrManager(config: Self.config)
        try await manager.loadModels(from: cacheDir)
        self.manager = manager
        streamedSampleCount = nil
        readyState.withLock { $0 = true }
        progressHandler?(1, "Ready")
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard let manager else {
            throw TranscriptionError.loadFailed
        }
        defer { streamedSampleCount = nil }

        try await append(samples, to: manager)
        return try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeStreaming(samples: [Float], language: String?) async throws -> String {
        guard let manager else {
            throw TranscriptionError.loadFailed
        }

        try await append(samples, to: manager)
        try await manager.processBufferedAudio()
        return await manager.getPartialTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetStreamingTranscription() {
        streamedSampleCount = nil
    }

    func unload() {
        readyState.withLock { $0 = false }
        streamedSampleCount = nil
        manager = nil
    }

    /// Hands the manager the part of the recording it has not seen.
    private func append(_ samples: [Float], to manager: StreamingUnifiedAsrManager) async throws {
        let start: Int
        if let unseen = Self.unseenStart(streamedSampleCount: streamedSampleCount, sampleCount: samples.count) {
            start = unseen
        } else {
            try await manager.reset()
            start = 0
        }
        streamedSampleCount = samples.count

        guard start < samples.count else { return }
        try await manager.appendAudio(Self.makePCMBuffer(from: samples[start...]))
    }

    /// Where the unseen part of a recording starts, or nil when the manager
    /// needs a new session. Each call gets the whole recording so far, so one
    /// shorter than what was streamed is a new recording.
    nonisolated static func unseenStart(streamedSampleCount: Int?, sampleCount: Int) -> Int? {
        guard let streamedSampleCount, streamedSampleCount <= sampleCount else { return nil }
        return streamedSampleCount
    }

    private static let inputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private static func makePCMBuffer(from samples: ArraySlice<Float>) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channelData = buffer.floatChannelData else {
            throw TranscriptionError.transcriptionFailed
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress {
                channelData[0].update(from: base, count: samples.count)
            }
        }
        return buffer
    }
}
