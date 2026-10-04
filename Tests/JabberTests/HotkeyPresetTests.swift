import Carbon
import XCTest
@testable import Jabber

final class HotkeyPresetTests: XCTestCase {
    func testPresetForShortcut() {
        let tests: [String: (shortcut: HotkeyShortcut, want: HotkeyPreset?)] = [
            "Option Space": (.defaultShortcut, .optionSpace),
            "Right Option": (HotkeyShortcut(keyCode: UInt32(kVK_RightOption), modifiers: 0), .rightOption),
            "Fn": (HotkeyShortcut(keyCode: UInt32(kVK_Function), modifiers: 0), .fn),
            "Left Option is custom": (HotkeyShortcut(keyCode: UInt32(kVK_Option), modifiers: 0), nil),
            "Control Option D is custom": (
                HotkeyShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey)),
                nil
            )
        ]

        for (name, tc) in tests {
            XCTAssertEqual(HotkeyPreset(shortcut: tc.shortcut), tc.want, name)
        }
    }

    func testPresetsAreValidShortcuts() {
        for preset in HotkeyPreset.allCases {
            XCTAssertNil(preset.shortcut.validationError, "\(preset)")
        }
    }
}
