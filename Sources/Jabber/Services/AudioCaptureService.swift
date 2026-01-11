import AVFoundation
import Foundation
import os

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000
    private let converterQueue = DispatchQueue(label: "com.jabber.audioconverter")
    private var converter: AVAudioConverter?

    private let queue = DispatchQueue(label: "com.jabber.audiocapture")
    private var capturedSamples: [Float] = []
    private var _isCapturing = false
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AudioCaptureService")

    var onAudioLevel: ((Float) -> Void)?
    var onConversionError: ((Error) -> Void)?

    private var isCapturing: Bool {
        get { queue.sync { _isCapturing } }
        set { queue.sync { _isCapturing = newValue } }
    }

    private func getConverter() -> AVAudioConverter? {
        converterQueue.sync { converter }
    }

    private func setConverter(_ newConverter: AVAudioConverter?) {
        converterQueue.sync { converter = newConverter }
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        queue.sync { capturedSamples.removeAll() }

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

        isCapturing = true
        do {
            try engine.start()
        } catch {
            stopCapture()
            throw error
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setConverter(nil)
    }

    func currentSamples() -> [Float] {
        queue.sync { capturedSamples }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Safely capture converter reference before checking state
        guard let converter = getConverter() else { return }
        guard isCapturing else { return }

        let rms = calculateRms(from: buffer)
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(rms)
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

        if let channelData = convertedBuffer.floatChannelData?[0] {
            let frames = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))

            queue.async { [weak self] in
                self?.capturedSamples.append(contentsOf: samples)
            }
        }
    }

    private func calculateRms(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames {
            sum += channelData[i] * channelData[i]
        }
        return sqrt(sum / Float(frames))
    }

    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> (buffer: AVAudioPCMBuffer?, error: Error?) {
        // Convert to 16kHz mono
        let outputFormat = converter.outputFormat
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(targetSampleRate / 10)
        ) else {
            return (nil, nil)
        }

        var error: NSError?
        var hasProvidedBuffer = false

        // Capture buffer in the conversion callback to avoid race conditions
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            guard !hasProvidedBuffer else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            hasProvidedBuffer = true
            return buffer
        }

        return (convertedBuffer, error)
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
