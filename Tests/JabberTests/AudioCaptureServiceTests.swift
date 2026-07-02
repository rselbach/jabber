import AVFoundation
import XCTest
@testable import Jabber

final class AudioCaptureServiceTests: XCTestCase {
    func testOutputFrameCapacity() {
        // 48000->16000 with 1024 input frames is 341.33, which must round
        // up to 342 rather than truncating to 341 and dropping samples.
        let cases: [String: (inputFrames: AVAudioFrameCount,
                             inputRate: Double,
                             outputRate: Double,
                             want: AVAudioFrameCount)] = [
            "downsample 48k->16k rounds up": (1024, 48_000, 16_000, 342),
            "identity rate preserves frames": (1024, 48_000, 48_000, 1024),
            "upsample 16k->48k multiplies up": (1024, 16_000, 48_000, 3072),
            "zero frames floors to one": (0, 48_000, 16_000, 1),
            "one frame floors to one": (1, 48_000, 16_000, 1)
        ]

        for (name, tc) in cases {
            let got = AudioCaptureService.outputFrameCapacity(
                inputFrames: tc.inputFrames,
                inputRate: tc.inputRate,
                outputRate: tc.outputRate
            )
            XCTAssertEqual(got, tc.want, name)
        }
    }
}
