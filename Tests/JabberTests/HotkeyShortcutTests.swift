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

    func testDefaultActivationModeIsHold() {
        XCTAssertEqual(HotkeyActivationMode.defaultMode, .hold)
        XCTAssertEqual(HotkeyActivationMode.hold.displayName, "Hold")
        XCTAssertEqual(HotkeyActivationMode.toggle.displayName, "Toggle")
        XCTAssertEqual(HotkeyActivationMode.automatic.displayName, "Automatic")
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

    func testModifierOnlyShortcutIsAllowedAndDetected() {
        let rightOption = HotkeyShortcut(
            keyCode: UInt32(kVK_RightOption),
            modifiers: 0
        )

        XCTAssertTrue(rightOption.isModifierOnly)
        XCTAssertNil(rightOption.validationError)
        XCTAssertEqual(rightOption.displayString, "Right Option")
    }

    func testModifierOnlyCoversEveryStandaloneModifierKey() {
        let codes: [UInt32] = [
            UInt32(kVK_Command), UInt32(kVK_RightCommand),
            UInt32(kVK_Shift), UInt32(kVK_RightShift),
            UInt32(kVK_Option), UInt32(kVK_RightOption),
            UInt32(kVK_Control), UInt32(kVK_RightControl)
        ]

        for code in codes {
            let shortcut = HotkeyShortcut(keyCode: code, modifiers: 0)
            XCTAssertTrue(shortcut.isModifierOnly, "expected modifier-only for key code \(code)")
            XCTAssertNil(shortcut.validationError, "expected valid shortcut for key code \(code)")
        }
    }

    func testModifierOnlyRequiresNoExtraModifiers() {
        // Right Option held alongside Command is not a lone-modifier shortcut
        // and should not claim to be modifier-only.
        let withExtra = HotkeyShortcut(
            keyCode: UInt32(kVK_RightOption),
            modifiers: UInt32(cmdKey)
        )

        XCTAssertFalse(withExtra.isModifierOnly)
    }

    func testCarbonModifierMappingForKeyCodes() {
        XCTAssertEqual(HotkeyShortcut.carbonModifier(forKeyCode: UInt32(kVK_RightOption)), UInt32(optionKey))
        XCTAssertEqual(HotkeyShortcut.carbonModifier(forKeyCode: UInt32(kVK_Option)), UInt32(optionKey))
        XCTAssertEqual(HotkeyShortcut.carbonModifier(forKeyCode: UInt32(kVK_RightCommand)), UInt32(cmdKey))
        XCTAssertEqual(HotkeyShortcut.carbonModifier(forKeyCode: UInt32(kVK_RightShift)), UInt32(shiftKey))
        XCTAssertEqual(HotkeyShortcut.carbonModifier(forKeyCode: UInt32(kVK_RightControl)), UInt32(controlKey))
        XCTAssertNil(HotkeyShortcut.carbonModifier(forKeyCode: UInt32(kVK_Space)))
    }
}
