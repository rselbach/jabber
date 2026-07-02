@preconcurrency import AVFoundation
import Foundation
import os

@MainActor
final class AudioCaptureService {
    private var engineStorage: AnyObject?
    private let targetSampleRate: Double = 16_000
    private let converterQueue = DispatchQueue(label: "com.jabber.audioconverter")
    nonisolated(unsafe) private var converter: AVAudioConverter?
    private static let initialCapturedSampleCapacity = 16_000 * 60

    private let queue = DispatchQueue(label: "com.jabber.audiocapture")
    nonisolated(unsafe) private var lastLevelUpdate: CFAbsoluteTime = 0
    nonisolated(unsafe) private var capturedSamples: [Float]
    nonisolated(unsafe) private var _isCapturing = false
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AudioCaptureService")

    var onAudioLevel: ((Float) -> Void)?
    var onConversionError: ((Error) -> Void)?

    init() {
        capturedSamples = []
        capturedSamples.reserveCapacity(Self.initialCapturedSampleCapacity)
    }

    private var isCapturing: Bool {
        get { queue.sync { _isCapturing } }
        set { queue.sync { _isCapturing = newValue } }
    }

    nonisolated private func getConverter() -> AVAudioConverter? {
        converterQueue.sync { converter }
    }

    nonisolated private func setConverter(_ newConverter: AVAudioConverter?) {
        converterQueue.sync { converter = newConverter }
    }

    private func audioEngine() -> AVAudioEngine {
        if let engine = engineStorage as? AVAudioEngine {
            return engine
        }

        let engine = AVAudioEngine()
        engineStorage = engine
        return engine
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        queue.sync {
            capturedSamples.removeAll(keepingCapacity: true)
        }

        let engine = audioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        setConverter(converter)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        queue.sync {
            _isCapturing = true
        }
        do {
            try engine.start()
        } catch {
            stopCapture()
            throw error
        }
    }

    func stopCapture() {
        let wasCapturing = queue.sync {
            guard _isCapturing else { return false }
            _isCapturing = false
            return true
        }
        guard wasCapturing else { return }
        guard let engine = engineStorage as? AVAudioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setConverter(nil)
    }

    func currentSamples() -> [Float] {
        queue.sync {
            capturedSamples
        }
    }

    nonisolated private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = getConverter() else { return }

        let rms = calculateRms(from: buffer)
        let now = CFAbsoluteTimeGetCurrent()
        let shouldReportLevel: Bool = queue.sync {
            guard _isCapturing else { return false }
            if now - lastLevelUpdate >= 1.0 / 30.0 {
                lastLevelUpdate = now
                return true
            }
            return false
        }
        if shouldReportLevel {
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(rms)
            }
        }

        let conversionResult = convertBuffer(buffer, using: converter)
        if let error = conversionResult.error {
            logger.error("Audio conversion failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onConversionError?(AudioCaptureError.conversionFailed(error))
            }
            return
        }

        guard let convertedBuffer = conversionResult.buffer else { return }

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let frames = Int(convertedBuffer.frameLength)
        guard frames > 0 else { return }

        let samples = UnsafeBufferPointer(start: channelData, count: frames)
        queue.sync {
            guard _isCapturing else { return }
            capturedSamples.append(contentsOf: samples)
        }
    }

    nonisolated private func calculateRms(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        for i in 0 ..< frames {
            sum += channelData[i] * channelData[i]
        }
        return min(1, sqrt(max(0, sum / Float(frames))))
    }

    /// output frame capacity needed to resample `inputFrames` from
    /// `inputRate` to `outputRate`; rounds up so no samples drop and is
    /// floored at one frame to keep downstream buffers non-empty.
    nonisolated static func outputFrameCapacity(
        inputFrames: AVAudioFrameCount,
        inputRate: Double,
        outputRate: Double
    ) -> AVAudioFrameCount {
        let raw = Double(inputFrames) * outputRate / inputRate
        return AVAudioFrameCount(max(1, raw.rounded(.up)))
    }

    nonisolated private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> (buffer: AVAudioPCMBuffer?, error: Error?) {
        // Convert to 16kHz mono
        let outputFormat = converter.outputFormat
        let outputFrameCapacity = Self.outputFrameCapacity(
            inputFrames: buffer.frameLength,
            inputRate: buffer.format.sampleRate,
            outputRate: outputFormat.sampleRate
        )
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return (nil, nil)
        }

        var error: NSError?
        let inputState = AudioConverterInputState()

        // Capture buffer in the conversion callback to avoid race conditions
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            guard inputState.claimBuffer() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        return (convertedBuffer, error)
    }
}

private final class AudioConverterInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasProvidedBuffer = false

    func claimBuffer() -> Bool {
        lock.withLock {
            guard !hasProvidedBuffer else { return false }
            hasProvidedBuffer = true
            return true
        }
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case invalidFormat
    case converterUnavailable
    case conversionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format configuration"
        case .converterUnavailable:
            return "Audio converter could not be created"
        case .conversionFailed(let error):
            return "Audio conversion failed: \(error.localizedDescription)"
        }
    }
}
