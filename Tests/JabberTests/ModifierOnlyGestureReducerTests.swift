import XCTest
@testable import Jabber

final class ModifierOnlyGestureReducerTests: XCTestCase {
    func testSoloHoldFiresOnlyAfterDebounceThenKeyUpStops() {
        var g = ModifierOnlyGestureReducer()

        // Press the modifier: nothing fires, but caller must schedule debounce.
        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.state, .pending)

        // Debounce elapses with no other key: now fire key-down.
        XCTAssertEqual(g.handle(.debounceElapsed), .fireDown)
        XCTAssertEqual(g.state, .active)

        // Release: still stops the hold (preserves hold / push-to-talk modes).
        XCTAssertEqual(g.handle(.modifierUp), .fireUp)
        XCTAssertEqual(g.state, .idle)
    }

    func testReleaseBeforeDebounceCancelsStart() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.modifierUp), .cancelStart)
        XCTAssertEqual(g.state, .idle)

        // A late debounce tick must not fire anything.
        XCTAssertEqual(g.handle(.debounceElapsed), .none)
    }

    func testOtherKeyBeforeDebounceCancelsStartAndSuppressesKeyUp() {
        // Reproduces Option+E typing: Option down, then E down before debounce.
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.otherKeyDown), .cancelStart)
        XCTAssertTrue(g.otherKeyPressedDuringModifier)

        // Debounce tick arriving after the cancel is a no-op.
        XCTAssertEqual(g.handle(.debounceElapsed), .none)

        // Releasing the modifier must not fire key-up, since key-down never ran.
        XCTAssertEqual(g.handle(.modifierUp), .none)
        XCTAssertFalse(g.otherKeyPressedDuringModifier)
    }

    func testOtherKeyAfterStartIsIgnoredButKeyUpStillStops() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.debounceElapsed), .fireDown)
        XCTAssertEqual(g.state, .active)

        // Another key while recording is active neither re-fires nor cancels.
        XCTAssertEqual(g.handle(.otherKeyDown), .none)
        XCTAssertEqual(g.state, .active)

        // Release still stops the hold.
        XCTAssertEqual(g.handle(.modifierUp), .fireUp)
        XCTAssertEqual(g.state, .idle)
    }

    func testRepeatModifierDownDoesNotReArm() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        // A duplicate down event (chatter) while pending must not re-schedule.
        XCTAssertEqual(g.handle(.modifierDown), .none)
        XCTAssertEqual(g.state, .pending)
    }

    func testInputsAreNoOpWhenIdle() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierUp), .none)
        XCTAssertEqual(g.handle(.otherKeyDown), .none)
        XCTAssertEqual(g.handle(.debounceElapsed), .none)
        XCTAssertEqual(g.handle(.tapDisabled), .none)
        XCTAssertEqual(g.state, .idle)
    }

    func testTapDisabledWhilePendingCancelsStartAndSuppressesDebounce() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.tapDisabled), .cancelStart)
        XCTAssertEqual(g.state, .idle)

        // A stale debounce tick after the tap-disable teardown must never start.
        XCTAssertEqual(g.handle(.debounceElapsed), .none)
    }

    func testTapDisabledWhileActiveFiresKeyUpAndReturnsIdle() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.debounceElapsed), .fireDown)
        XCTAssertEqual(g.handle(.tapDisabled), .fireUp)
        XCTAssertEqual(g.state, .idle)
    }

    func testCanReArmAfterCancel() {
        var g = ModifierOnlyGestureReducer()

        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.otherKeyDown), .cancelStart)

        // The modifier must be released before it can be pressed again.
        XCTAssertEqual(g.handle(.modifierUp), .none)
        XCTAssertEqual(g.state, .idle)

        // A second deliberate hold schedules and fires again.
        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.debounceElapsed), .fireDown)
        XCTAssertEqual(g.state, .active)
    }

    func testResetClearsState() {
        var g = ModifierOnlyGestureReducer()
        _ = g.handle(.modifierDown)
        _ = g.handle(.otherKeyDown)

        g.reset()

        XCTAssertEqual(g.state, .idle)
        XCTAssertFalse(g.otherKeyPressedDuringModifier)
    }

    func testDebounceIntervalIsInRequiredRange() {
        XCTAssertGreaterThanOrEqual(ModifierOnlyGestureReducer.debounceInterval, 0.10)
        XCTAssertLessThanOrEqual(ModifierOnlyGestureReducer.debounceInterval, 0.15)
    }
}
