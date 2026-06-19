import XCTest
@testable import Jabber

final class AudioSpeechDetectorTests: XCTestCase {
    func testEmptyAudioIsRejectedWithoutWarning() {
        let assessment = AudioSpeechDetector.assess(samples: [])

        XCTAssertFalse(assessment.shouldTranscribe)
        XCTAssertEqual(assessment.rejectionReason, .empty)
        XCTAssertFalse(assessment.shouldShowNoSpeechWarning)
    }

    func testShortAudioIsRejectedWithoutWarning() {
        let samples = Array(repeating: Float(0.1), count: 1_000)

        let assessment = AudioSpeechDetector.assess(samples: samples)

        XCTAssertFalse(assessment.shouldTranscribe)
        XCTAssertFalse(assessment.shouldShowNoSpeechWarning)
        guard case .tooShort = assessment.rejectionReason else {
            XCTFail("Expected tooShort rejection")
            return
        }
    }

    func testQuietAudioIsRejectedWithWarning() {
        let samples = Array(repeating: Float(0.001), count: 16_000)

        let assessment = AudioSpeechDetector.assess(samples: samples)

        XCTAssertFalse(assessment.shouldTranscribe)
        XCTAssertTrue(assessment.shouldShowNoSpeechWarning)
        guard case .tooQuiet = assessment.rejectionReason else {
            XCTFail("Expected tooQuiet rejection")
            return
        }
    }

    func testSpeechLikeAudioIsAccepted() {
        let samples = makeSineWave(amplitude: 0.05, sampleCount: 16_000)

        let assessment = AudioSpeechDetector.assess(samples: samples)

        XCTAssertTrue(assessment.shouldTranscribe)
        XCTAssertNil(assessment.rejectionReason)
        XCTAssertGreaterThanOrEqual(assessment.duration, 1)
        XCTAssertGreaterThan(assessment.rms, 0.003)
        XCTAssertGreaterThan(assessment.peak, 0.015)
        XCTAssertGreaterThanOrEqual(assessment.activeDuration, 0.08)
    }

    private func makeSineWave(amplitude: Float, sampleCount: Int) -> [Float] {
        let frequency = 220.0
        let sampleRate = 16_000.0

        return (0 ..< sampleCount).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            return amplitude * Float(sin(phase))
        }
    }
}
