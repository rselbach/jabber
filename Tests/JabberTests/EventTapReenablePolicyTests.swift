import Foundation
import XCTest
@testable import Jabber

/// Tests for `EventTapReenablePolicy`, the pure backoff decision used by
/// `HotkeyManager` when the system disables the modifier-only CGEventTap.
///
/// The policy bounds a runaway disable→re-enable loop (which happens when
/// Accessibility permission is revoked): up to `maxReenables` rapid re-disables
/// within `rapidWindow` re-enable the tap; the disable that pushes the in-window
/// count past `maxReenables` trips give-up. The window filter drops stale
/// disables so "the tap stayed alive" needs no timer.
final class EventTapReenablePolicyTests: XCTestCase {
    func testShouldReenableTable() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        func d(_ seconds: TimeInterval) -> Date {
            t0.addingTimeInterval(seconds)
        }

        struct Case {
            let name: String
            let recent: [Date]
            let newDisable: Date
            let maxReenables: Int
            let rapidWindow: TimeInterval
            let wantReenable: Bool
            let wantUpdatedCount: Int
        }

        let tests: [Case] = [
            .init(
                name: "first disable re-enables",
                recent: [], newDisable: d(0),
                maxReenables: 5, rapidWindow: 5,
                wantReenable: true, wantUpdatedCount: 1
            ),
            .init(
                name: "fifth disable within window still re-enables (count == max)",
                recent: [d(0), d(1), d(2), d(3)], newDisable: d(4),
                maxReenables: 5, rapidWindow: 5,
                wantReenable: true, wantUpdatedCount: 5
            ),
            // THE BUG: the disable that exceeds the bound must stop the loop.
            .init(
                name: "sixth disable within window gives up (count > max)",
                recent: [d(0), d(1), d(2), d(3), d(4)], newDisable: d(4.5),
                maxReenables: 5, rapidWindow: 5,
                wantReenable: false, wantUpdatedCount: 6
            ),
            .init(
                name: "disables outside the window are dropped",
                // Only the last two are within the 5s window of newDisable=d(20).
                recent: [d(0), d(5), d(16), d(18)], newDisable: d(20),
                maxReenables: 5, rapidWindow: 5,
                wantReenable: true, wantUpdatedCount: 3
            ),
            .init(
                name: "disable exactly at the cutoff age is kept (>=)",
                recent: [d(15)], newDisable: d(20),
                maxReenables: 5, rapidWindow: 5,
                wantReenable: true, wantUpdatedCount: 2
            ),
            .init(
                name: "disable just past the cutoff age is dropped",
                recent: [d(14.9)], newDisable: d(20),
                maxReenables: 5, rapidWindow: 5,
                wantReenable: true, wantUpdatedCount: 1
            ),
            .init(
                name: "custom maxReenables of 1 gives up on the second disable",
                recent: [d(0)], newDisable: d(0.5),
                maxReenables: 1, rapidWindow: 5,
                wantReenable: false, wantUpdatedCount: 2
            ),
        ]

        for tc in tests {
            let result = EventTapReenablePolicy.shouldReenable(
                recentDisableTimes: tc.recent,
                newDisableTime: tc.newDisable,
                maxReenables: tc.maxReenables,
                rapidWindow: tc.rapidWindow
            )
            XCTAssertEqual(result.reenable, tc.wantReenable, tc.name)
            XCTAssertEqual(result.updated.count, tc.wantUpdatedCount, tc.name)
            // The new disable is always appended last.
            XCTAssertEqual(result.updated.last, tc.newDisable, tc.name)
        }
    }

    /// Reproduces the manager's call sequence during a real runaway loop:
    /// repeated disables 0.5s apart. The first five re-enable; the sixth trips
    /// give-up. Spreading disables beyond the window would recover, which this
    /// also asserts.
    func testRunawaySequenceGivesUpThenRecoversAfterWindow() {
        let start = Date(timeIntervalSince1970: 2_000)
        var recent: [Date] = []
        // Five rapid disables: all re-enable.
        for i in 0 ..< 5 {
            let result = EventTapReenablePolicy.shouldReenable(
                recentDisableTimes: recent,
                newDisableTime: start.addingTimeInterval(Double(i) * 0.5)
            )
            XCTAssertTrue(result.reenable, "disable #\(i + 1) should re-enable")
            recent = result.updated
        }
        // Sixth rapid disable: give up.
        let sixth = EventTapReenablePolicy.shouldReenable(
            recentDisableTimes: recent,
            newDisableTime: start.addingTimeInterval(2.5)
        )
        XCTAssertFalse(sixth.reenable, "sixth rapid disable should give up")
        XCTAssertEqual(sixth.updated.count, 6)

        // After the window passes with no further disables, a new disable starts
        // fresh (the stale history is dropped) and re-enables again.
        let recovered = EventTapReenablePolicy.shouldReenable(
            recentDisableTimes: recent,
            newDisableTime: start.addingTimeInterval(100)
        )
        XCTAssertTrue(recovered.reenable, "disable well past the window should recover")
        XCTAssertEqual(recovered.updated.count, 1)
    }

    func testDefaultConstantsAreSensible() {
        XCTAssertEqual(EventTapReenablePolicy.maxReenables, 5)
        XCTAssertEqual(EventTapReenablePolicy.rapidWindow, 5)
    }
}
