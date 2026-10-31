import XCTest
@testable import Jabber

@MainActor
final class WaveformViewTests: XCTestCase {
    func testShowFallbackNoticeSetsActiveNotice() {
        let view = WaveformView()
        XCTAssertFalse(view.hasActiveFallbackNotice)

        view.showFallbackNotice(title: "Used Raw Transcript", message: "Refinement looked wrong.")

        XCTAssertTrue(view.hasActiveFallbackNotice)
        XCTAssertEqual(
            view.fallbackNotice,
            OverlayNotice(title: "Used Raw Transcript", message: "Refinement looked wrong.")
        )
    }

    func testRecordingClockRunsOnlyWhileRecording() {
        let cases: [String: (end: (WaveformView) -> Void, wantStartedAt: Date?)] = [
            "still recording": ({ _ in }, Date(timeIntervalSince1970: 1_000)),
            "transcribing": ({ $0.showProcessing() }, nil),
            "reset for a new session": ({ $0.reset() }, nil)
        ]

        for (name, tc) in cases {
            let view = WaveformView()
            view.startRecordingClock(limit: 900, startedAt: Date(timeIntervalSince1970: 1_000))
            tc.end(view)

            XCTAssertEqual(view.recordingStartedAt, tc.wantStartedAt, name)
            XCTAssertEqual(view.recordingLimit, 900, name)
        }
    }

    func testClearFallbackNoticeInvokesCallback() {
        let view = WaveformView()
        var cleared = false
        view.onFallbackNoticeCleared = { cleared = true }

        view.showFallbackNotice(title: "x", message: "y")
        view.clearFallbackNotice()

        XCTAssertFalse(view.hasActiveFallbackNotice)
        XCTAssertNil(view.fallbackNotice)
        XCTAssertTrue(cleared)
    }

    func testResetClearsNoticeWithoutFiringClearedCallback() {
        let view = WaveformView()
        var cleared = false
        view.onFallbackNoticeCleared = { cleared = true }

        view.showFallbackNotice(title: "x", message: "y")
        view.reset()

        // reset() abandons the notice (new session) and must NOT fire the
        // cleared callback, which would complete a stale deferred hide.
        XCTAssertFalse(view.hasActiveFallbackNotice)
        XCTAssertNil(view.fallbackNotice)
        XCTAssertFalse(cleared)
    }

    func testSilentInputDetector() {
        let tests: [String: (levels: [(level: Float, time: TimeInterval)], want: Bool)] = [
            "silent long enough": ([(0, 0), (0.0001, 1), (0, 1.5)], true),
            "silent too briefly": ([(0, 0), (0, 1.4)], false),
            "room noise is not silence": ([(0.001, 0), (0.001, 2)], false),
            "sound restarts the clock": ([(0, 0), (0.01, 1), (0, 1.2), (0, 2.6)], false),
            "sound clears it": ([(0, 0), (0, 2), (0.01, 2.1)], false)
        ]
        for (name, tc) in tests {
            var detector = SilentInputDetector()
            var got = false
            for sample in tc.levels {
                got = detector.observe(level: sample.level, at: sample.time)
            }
            XCTAssertEqual(got, tc.want, name)
        }
    }

    func testSilentInputClearsOnReset() {
        let view = WaveformView()
        view.addLevel(0, at: 0)
        view.addLevel(0, at: 2)
        XCTAssertTrue(view.isInputSilent)

        view.reset()

        XCTAssertFalse(view.isInputSilent)
    }
}
