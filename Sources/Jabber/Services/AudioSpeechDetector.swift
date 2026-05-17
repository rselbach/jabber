import Foundation

struct AudioSpeechAssessment: Equatable {
    enum RejectionReason: Equatable {
        case empty
        case tooShort(duration: Double)
        case tooQuiet(rms: Float, activeDuration: Double)
    }

    let duration: Double
    let rms: Float
    let peak: Float
    let activeDuration: Double
    let rejectionReason: RejectionReason?

    var shouldTranscribe: Bool {
        rejectionReason == nil
    }

    var shouldShowNoSpeechWarning: Bool {
        switch rejectionReason {
        case .empty, .tooShort:
            return false
        case .tooQuiet:
            return true
        case nil:
            return false
        }
    }
}

enum AudioSpeechDetector {
    private static let sampleRate = 16_000.0
    private static let minDuration = 0.25
    private static let minOverallRMS: Float = 0.003
    private static let minPeak: Float = 0.015
    private static let frameSize = 320
    private static let activeFrameRMSThreshold: Float = 0.006
    private static let minActiveDuration = 0.08

    static func assess(samples: [Float]) -> AudioSpeechAssessment {
        guard !samples.isEmpty else {
            return AudioSpeechAssessment(
                duration: 0,
                rms: 0,
                peak: 0,
                activeDuration: 0,
                rejectionReason: .empty
            )
        }

        let duration = Double(samples.count) / sampleRate
        let rms = calculateRMS(samples)
        let peak = calculatePeak(samples)
        let activeDuration = calculateActiveDuration(samples)

        guard duration >= minDuration else {
            return AudioSpeechAssessment(
                duration: duration,
                rms: rms,
                peak: peak,
                activeDuration: activeDuration,
                rejectionReason: .tooShort(duration: duration)
            )
        }

        guard rms >= minOverallRMS,
              peak >= minPeak,
              activeDuration >= minActiveDuration else {
            return AudioSpeechAssessment(
                duration: duration,
                rms: rms,
                peak: peak,
                activeDuration: activeDuration,
                rejectionReason: .tooQuiet(rms: rms, activeDuration: activeDuration)
            )
        }

        return AudioSpeechAssessment(
            duration: duration,
            rms: rms,
            peak: peak,
            activeDuration: activeDuration,
            rejectionReason: nil
        )
    }

    private static func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(max(0, sum / Float(samples.count)))
    }

    private static func calculatePeak(_ samples: [Float]) -> Float {
        var peak: Float = 0
        for sample in samples {
            peak = max(peak, abs(sample))
        }
        return peak
    }

    private static func calculateActiveDuration(_ samples: [Float]) -> Double {
        var activeSampleCount = 0
        var start = 0

        while start < samples.count {
            let end = min(start + frameSize, samples.count)
            let frame = samples[start..<end]
            if calculateFrameRMS(frame) >= activeFrameRMSThreshold {
                activeSampleCount += end - start
            }
            start = end
        }

        return Double(activeSampleCount) / sampleRate
    }

    private static func calculateFrameRMS(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }

        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(max(0, sum / Float(samples.count)))
    }
}
