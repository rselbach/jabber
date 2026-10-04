import XCTest
@testable import Jabber

final class CarbonHotkeyRouteTests: XCTestCase {
    func testRoutesEachHotkeyByID() {
        let cases: [String: (hotKeyID: UInt32, isPressed: Bool, want: CarbonHotkeyRoute)] = [
            "dictation press": (CarbonHotkeyRoute.dictationHotKeyID, true, .dictationDown),
            "dictation release": (CarbonHotkeyRoute.dictationHotKeyID, false, .dictationUp),
            "escape press cancels": (CarbonHotkeyRoute.cancelHotKeyID, true, .cancel),
            "escape release does nothing": (CarbonHotkeyRoute.cancelHotKeyID, false, .ignore),
            "unknown hotkey": (99, true, .ignore)
        ]

        for (name, tc) in cases {
            XCTAssertEqual(CarbonHotkeyRoute.route(hotKeyID: tc.hotKeyID, isPressed: tc.isPressed), tc.want, name)
        }
    }
}
