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

        var sumOfSquares: Float = 0
        var peak: Float = 0
        var activeSampleCount = 0
        var frameSumOfSquares: Float = 0
        var frameCount = 0

        for sample in samples {
            let absSample = abs(sample)
            if absSample > peak { peak = absSample }
            let squared = sample * sample
            sumOfSquares += squared
            frameSumOfSquares += squared
            frameCount += 1

            if frameCount == frameSize {
                if sqrt(max(0, frameSumOfSquares / Float(frameSize))) >= activeFrameRMSThreshold {
                    activeSampleCount += frameCount
                }
                frameSumOfSquares = 0
                frameCount = 0
            }
        }

        if frameCount > 0 {
            if sqrt(max(0, frameSumOfSquares / Float(frameCount))) >= activeFrameRMSThreshold {
                activeSampleCount += frameCount
            }
        }

        let rms = sqrt(max(0, sumOfSquares / Float(samples.count)))
        let activeDuration = Double(activeSampleCount) / sampleRate

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
}
