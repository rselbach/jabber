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

        overlay.showFallbackNotice("session A — raw transcript used")
        XCTAssertTrue(overlay.waveformView?.hasActiveFallbackNotice ?? false)

        overlay.hide()
        // Deferred: super.hide() must NOT run, so the token stays put.
        XCTAssertEqual(overlay.visibilityToken, tokenAfterFirstShow)

        // Session B begins. onShow must clear the stale pendingHide.
        overlay.show()
        let tokenAfterSecondShow = overlay.visibilityToken
        XCTAssertEqual(tokenAfterSecondShow, 2)

        overlay.showFallbackNotice("session B — refinement failed")
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

        // Simulate a screen change (external display unplugged / resolution
        // change): the injected frame moves. The cached panel must follow.
        overlay.injectedFrame = NSRect(x: 2000, y: 500, width: 400, height: 104)
        overlay.show()
        XCTAssertEqual(
            overlay.window?.frame,
            NSRect(x: 2000, y: 500, width: 400, height: 104),
            "show() must reposition the cached panel against the current screen"
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
}
