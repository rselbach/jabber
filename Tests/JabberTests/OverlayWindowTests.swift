import AppKit
import XCTest
@testable import Jabber

@MainActor
final class OverlayWindowTests: XCTestCase {
    // Regression: session A ends while a fallback notice is on screen, so
    // hide() is deferred (pendingHide = true). The user starts session B
    // inside the notice window; show() resets the notice silently. Without
    // clearing pendingHide on show, session B's own fallback-notice auto-clear
    // fires fallbackNoticeCleared(), sees the stale pendingHide, and hides the
    // overlay while session B is still active. visibilityToken bumps on every
    // super.hide() call, so it's the synchronous proxy for "overlay got hidden".
    func testDeferredHideDoesNotFireAfterNewSessionShow() {
        let overlay = TestOverlayWindow()

        overlay.show()
        let tokenAfterFirstShow = overlay.visibilityToken
        XCTAssertEqual(tokenAfterFirstShow, 1)

        overlay.showFallbackNotice(title: "Session A", message: "Raw transcript used.")
        XCTAssertTrue(overlay.waveformView?.hasActiveFallbackNotice ?? false)

        overlay.hide()
        // Deferred: super.hide() must NOT run, so the token stays put.
        XCTAssertEqual(overlay.visibilityToken, tokenAfterFirstShow)

        // Session B begins. onShow must clear the stale pendingHide.
        overlay.show()
        let tokenAfterSecondShow = overlay.visibilityToken
        XCTAssertEqual(tokenAfterSecondShow, 2)

        overlay.showFallbackNotice(title: "Session B", message: "Refinement failed.")
        XCTAssertTrue(overlay.waveformView?.hasActiveFallbackNotice ?? false)

        // Simulate session B's notice auto-clearing. The stale deferred hide
        // from session A must NOT complete here — session B is still active.
        overlay.waveformView?.clearFallbackNotice()

        XCTAssertEqual(
            overlay.visibilityToken,
            tokenAfterSecondShow,
            "stale pendingHide leaked into session B and hid the active overlay"
        )
    }

    /// NotificationService routes messages it cannot post as notifications to
    /// the overlay, usually while no dictation is running. The notice must
    /// bring the panel up itself and take it down once the notice clears.
    func testNoticeWhileIdleShowsPanelUntilNoticeClears() {
        let overlay = TestOverlayWindow()

        overlay.showFallbackNotice(title: "Model Not Ready", message: "Troy Barnes has to wait a moment.")

        XCTAssertEqual(overlay.window?.isVisible, true)
        XCTAssertTrue(overlay.hasActiveFallbackNotice)
        XCTAssertEqual(
            overlay.waveformView?.fallbackNotice,
            OverlayNotice(title: "Model Not Ready", message: "Troy Barnes has to wait a moment.")
        )
        let tokenWhileNoticeVisible = overlay.visibilityToken

        overlay.waveformView?.clearFallbackNotice()

        XCTAssertEqual(
            overlay.visibilityToken,
            tokenWhileNoticeVisible + 1,
            "clearing the notice must hide the panel it brought up"
        )
    }

    /// A notice that lands mid-session must not reset or hide the live
    /// overlay: it covers the content until it clears, then the session
    /// carries on with its state intact.
    func testNoticeDuringSessionKeepsSessionOverlay() {
        let overlay = TestOverlayWindow()
        overlay.show()
        overlay.updatePartialTranscription("Greendale is where I belong")
        let tokenDuringSession = overlay.visibilityToken

        overlay.showFallbackNotice(title: "Clipboard Restore Failed", message: "Señor Chang took it.")

        XCTAssertEqual(overlay.visibilityToken, tokenDuringSession, "a mid-session notice must not re-show or hide the overlay")
        XCTAssertTrue(overlay.hasActiveFallbackNotice)
        XCTAssertEqual(overlay.waveformView?.partialTranscription, "Greendale is where I belong")

        overlay.waveformView?.clearFallbackNotice()

        XCTAssertEqual(overlay.visibilityToken, tokenDuringSession, "the session still owns the overlay after the notice clears")
        XCTAssertEqual(overlay.waveformView?.partialTranscription, "Greendale is where I belong")
    }

    /// Session-end notices (No Speech Detected, Transcription Failed) arrive
    /// just after the session's hide started. The notice must interrupt that
    /// hide and keep the panel up until it clears.
    func testNoticeAfterSessionHideKeepsPanelUntilNoticeClears() {
        let overlay = TestOverlayWindow()
        overlay.show()
        overlay.hide()
        let tokenAfterSessionHide = overlay.visibilityToken

        overlay.showFallbackNotice(title: "No Speech Detected", message: "Abed said nothing.")

        XCTAssertEqual(overlay.visibilityToken, tokenAfterSessionHide + 1, "the notice must interrupt the in-flight hide")
        XCTAssertTrue(overlay.hasActiveFallbackNotice)

        overlay.waveformView?.clearFallbackNotice()

        XCTAssertEqual(overlay.visibilityToken, tokenAfterSessionHide + 2, "the panel must hide once the notice clears")
    }

    /// A dictation that starts while an idle notice is up takes over the
    /// panel. The notice is dropped and its auto-hide must not hide the
    /// new session.
    func testSessionStartDuringIdleNoticeTakesOverPanel() {
        let overlay = TestOverlayWindow()
        overlay.showFallbackNotice(title: "Still Transcribing", message: "Britta is still talking.")
        XCTAssertTrue(overlay.hasActiveFallbackNotice)
        let tokenWhileNoticeVisible = overlay.visibilityToken

        overlay.show()
        let tokenAfterSessionShow = overlay.visibilityToken

        XCTAssertEqual(tokenAfterSessionShow, tokenWhileNoticeVisible + 1, "a session show must take over the notice panel")
        XCTAssertFalse(overlay.hasActiveFallbackNotice)

        overlay.waveformView?.clearFallbackNotice()

        XCTAssertEqual(overlay.visibilityToken, tokenAfterSessionShow, "the dropped notice must not hide the session")
    }

    /// AppDelegate keeps the download overlay out of the notice's spot and
    /// restores it from this callback, so it must fire when the notice clears.
    func testClearingNoticeNotifiesOwner() {
        let overlay = TestOverlayWindow()
        var clearedCount = 0
        overlay.onFallbackNoticeCleared = { clearedCount += 1 }

        overlay.showFallbackNotice(title: "Model Download Failed", message: "Pierce unplugged the router.")
        overlay.waveformView?.clearFallbackNotice()

        XCTAssertEqual(clearedCount, 1)
    }

    // Regression: hide() during an in-flight hide bumped visibilityToken, so
    // the first hide's completion read the mismatch as "a show superseded me",
    // restored alpha on a still-ordered-in window (flash), and reset isHiding —
    // letting a following show() early-return while the second completion
    // ordered the window out (swallowed show). A hide must not interrupt an
    // in-flight hide; the token proxy makes that observable synchronously.
    func testHideDuringInFlightHideDoesNotInterruptIt() {
        let overlay = TestOverlayWindow()

        overlay.show()
        overlay.hide()
        let tokenAfterFirstHide = overlay.visibilityToken

        overlay.hide()
        XCTAssertEqual(
            overlay.visibilityToken,
            tokenAfterFirstHide,
            "a second hide must not bump the token of the in-flight hide"
        )
    }

    // Regression: the overlay panel is created once and cached, positioned
    // against NSScreen.main at creation time. Without recomputing on every
    // show(), unplugging the display it was created on strands it offscreen
    // and every future dictation shows an invisible overlay. show() must
    // reposition against the current screen on every call.
    func testShowRepositionsWindowOnEveryCall() {
        let overlay = TestOverlayWindow()

        // First show creates the panel and applies the injected frame.
        overlay.injectedFrame = NSRect(x: 100, y: 100, width: 400, height: 104)
        overlay.show()
        XCTAssertEqual(overlay.window?.frame, NSRect(x: 100, y: 100, width: 400, height: 104))

        // Simulate a real hide followed by a screen change (external display
        // unplugged / resolution change): the injected frame moves. The cached
        // panel must follow when it is shown again.
        overlay.window?.orderOut(nil)
        overlay.injectedFrame = NSRect(x: 2000, y: 500, width: 400, height: 104)
        overlay.show()
        XCTAssertEqual(
            overlay.window?.frame,
            NSRect(x: 2000, y: 500, width: 400, height: 104),
            "show() must reposition the cached panel against the current screen"
        )
    }

    func testShowSkipsVisibleWindow() {
        let overlay = TestOverlayWindow()

        overlay.show()
        let tokenAfterFirstShow = overlay.visibilityToken
        let repositionCountAfterFirstShow = overlay.repositionCount

        overlay.injectedFrame = NSRect(x: 2000, y: 500, width: 400, height: 104)
        overlay.show()

        XCTAssertEqual(overlay.visibilityToken, tokenAfterFirstShow)
        XCTAssertEqual(overlay.repositionCount, repositionCountAfterFirstShow)
        XCTAssertEqual(
            overlay.window?.frame,
            NSRect(x: 0, y: 0, width: 400, height: 104),
            "already-visible show() calls should not churn reposition/orderFront work"
        )
    }

    func testScreenFrameSelectsFrameContainingPoint() {
        let screenFrames = [
            NSRect(x: 0, y: 0, width: 1920, height: 1080),
            NSRect(x: 1920, y: 120, width: 2560, height: 1440),
            NSRect(x: -1280, y: 0, width: 1280, height: 720),
        ]

        XCTAssertEqual(
            OverlayScreenResolver.screenFrame(
                containing: NSPoint(x: 2200, y: 500),
                screenFrames: screenFrames
            ),
            1
        )
        XCTAssertEqual(
            OverlayScreenResolver.screenFrame(
                containing: NSPoint(x: -100, y: 300),
                screenFrames: screenFrames
            ),
            2
        )
    }

    func testScreenFrameFallsBackWhenPointIsOutsideAllFrames() {
        let screenFrames = [
            NSRect(x: 0, y: 0, width: 1920, height: 1080),
            NSRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]

        XCTAssertNil(
            OverlayScreenResolver.screenFrame(
                containing: NSPoint(x: 1919, y: 1200),
                screenFrames: screenFrames
            )
        )
    }
}

/// Minimal OverlayWindow subclass whose createWindow() doesn't depend on
/// NSScreen.main (unavailable in headless test runners). Wires the fallback
/// notice callback the same way the real createWindow does so the deferred-hide
/// path is exercised against the production OverlayWindow logic. Overrides
/// frameForCurrentScreen() to inject a deterministic frame so reposition-on-show
/// is testable without fabricating an NSScreen.
@MainActor
final class TestOverlayWindow: OverlayWindow {
    var injectedFrame: NSRect = .init(x: 0, y: 0, width: 400, height: 104)
    var repositionCount = 0

    override func createWindow() -> Bool {
        let panel = NSPanel(
            contentRect: injectedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let waveform = WaveformView()
        waveform.onFallbackNoticeCleared = { [weak self] in
            self?.fallbackNoticeCleared()
        }
        window = panel
        waveformView = waveform
        return true
    }

    override func frameForCurrentScreen() -> NSRect? {
        injectedFrame
    }

    override func reposition() {
        repositionCount += 1
        super.reposition()
    }
}
