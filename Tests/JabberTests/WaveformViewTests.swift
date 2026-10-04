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
}
