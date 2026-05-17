import AppKit
import Carbon
import XCTest
@testable import Jabber

final class HotkeyShortcutTests: XCTestCase {
    func testDefaultShortcutIsOptionSpace() {
        XCTAssertEqual(HotkeyShortcut.defaultShortcut.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotkeyShortcut.defaultShortcut.modifiers, UInt32(optionKey))
        XCTAssertEqual(HotkeyShortcut.defaultShortcut.displayString, "⌥ Space")
        XCTAssertNil(HotkeyShortcut.defaultShortcut.validationError)
    }

    func testDisplayStringIncludesModifierSymbolsInStableOrder() {
        let shortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )

        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘ A")
    }

    func testValidationRejectsShortcutWithoutRequiredModifier() {
        let noModifier = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: 0
        )
        let shiftOnly = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(shiftKey)
        )

        XCTAssertEqual(noModifier.validationError, .missingRequiredModifier)
        XCTAssertEqual(shiftOnly.validationError, .missingRequiredModifier)
    }

    func testValidationRejectsEscape() {
        let shortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_Escape),
            modifiers: UInt32(optionKey)
        )

        XCTAssertEqual(shortcut.validationError, .escapeKey)
    }

    func testCarbonModifiersFromAppKitFlags() {
        let modifiers = HotkeyShortcut.carbonModifiers(
            from: [.control, .option, .shift, .command]
        )

        XCTAssertEqual(
            modifiers,
            UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
    }
}
