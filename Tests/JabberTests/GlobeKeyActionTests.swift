import XCTest
@testable import Jabber

final class GlobeKeyActionTests: XCTestCase {
    func testActionForUsageType() {
        let tests: [String: (usageType: Int?, want: GlobeKeyAction, wantWarning: Bool)] = [
            "do nothing": (0, .doNothing, false),
            "change input source": (1, .changeInputSource, true),
            "show emoji and symbols": (2, .showEmojiAndSymbols, true),
            "start dictation": (3, .startDictation, true),
            "never set": (nil, .unknown, true),
            "unknown value": (7, .unknown, true)
        ]

        for (name, tc) in tests {
            let got = GlobeKeyAction(usageType: tc.usageType)
            XCTAssertEqual(got, tc.want, name)
            XCTAssertEqual(got.fnHotkeyWarning != nil, tc.wantWarning, name)
        }
    }
}
