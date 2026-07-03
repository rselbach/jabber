import XCTest
@testable import Jabber

@MainActor
final class WaveformViewTests: XCTestCase {
    func testShowFallbackNoticeSetsActiveNotice() {
        let view = WaveformView()
        XCTAssertFalse(view.hasActiveFallbackNotice)

        view.showFallbackNotice("Refinement looked wrong — used raw transcript")

        XCTAssertTrue(view.hasActiveFallbackNotice)
        XCTAssertEqual(view.fallbackNotice, "Refinement looked wrong — used raw transcript")
    }

    func testClearFallbackNoticeInvokesCallback() {
        let view = WaveformView()
        var cleared = false
        view.onFallbackNoticeCleared = { cleared = true }

        view.showFallbackNotice("x")
        view.clearFallbackNotice()

        XCTAssertFalse(view.hasActiveFallbackNotice)
        XCTAssertNil(view.fallbackNotice)
        XCTAssertTrue(cleared)
    }

    func testResetClearsNoticeWithoutFiringClearedCallback() {
        let view = WaveformView()
        var cleared = false
        view.onFallbackNoticeCleared = { cleared = true }

        view.showFallbackNotice("x")
        view.reset()

        // reset() abandons the notice (new session) and must NOT fire the
        // cleared callback, which would complete a stale deferred hide.
        XCTAssertFalse(view.hasActiveFallbackNotice)
        XCTAssertNil(view.fallbackNotice)
        XCTAssertFalse(cleared)
    }
}
