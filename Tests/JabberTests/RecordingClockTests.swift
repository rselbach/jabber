import XCTest
@testable import Jabber

final class RecordingClockTests: XCTestCase {
    func testClockCountsUpThenWarnsBeforeTheLimit() {
        let limit: TimeInterval = 900
        let cases: [String: (elapsed: TimeInterval, wantText: String, wantWarning: Bool)] = [
            "just started": (0, "0:00", false),
            "partial seconds round down": (7.9, "0:07", false),
            "over a minute": (65, "1:05", false),
            "just outside the warning window": (839.9, "13:59", false),
            "warning window starts": (840, "Stops in 1:00", true),
            "countdown rounds up": (855.2, "Stops in 0:45", true),
            "at the limit": (900, "Stops in 0:00", true),
            "past the limit": (905, "Stops in 0:00", true)
        ]

        for (name, tc) in cases {
            let got = RecordingClock(elapsed: tc.elapsed, limit: limit)
            XCTAssertEqual(got.text, tc.wantText, name)
            XCTAssertEqual(got.isWarning, tc.wantWarning, name)
        }
    }
}
