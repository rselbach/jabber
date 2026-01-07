import AVFoundation
import Foundation
import os

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000
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

    func startCapture() throws {
        guard !isCapturing else { return }

        queue.sync { capturedSamples.removeAll() }
        isCapturing = true

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

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        try engine.start()
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func currentSamples() -> [Float] {
        queue.sync { capturedSamples }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isCapturing, let converter else { return }

        // Calculate RMS for visualization
        if let channelData = buffer.floatChannelData?[0] {
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frames))
            DispatchQueue.main.async {
                self.onAudioLevel?(rms)
            }
        }

        // Convert to 16kHz mono
        guard let outputFormat = converter.outputFormat as AVAudioFormat?,
              let convertedBuffer = AVAudioPCMBuffer(
                  pcmFormat: outputFormat,
                  frameCapacity: AVAudioFrameCount(targetSampleRate / 10)
              ) else { return }

        var error: NSError?
        var hasData = true

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            guard hasData else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            hasData = false
            return buffer
        }

        if let error {
            logger.error("Audio conversion failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.onConversionError?(error)
            }
            return
        }

        if let channelData = convertedBuffer.floatChannelData?[0] {
            let frames = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))

            queue.async {
                self.capturedSamples.append(contentsOf: samples)
            }
        }
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case invalidFormat
    case conversionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format configuration"
        case .conversionFailed(let error):
            return "Audio conversion failed: \(error.localizedDescription)"
        }
    }
}
