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

    func testKeycapLabelsSplitModifiersAndKeepKeyNameWhole() {
        let tests: [String: (shortcut: HotkeyShortcut, want: [String])] = [
            "modifiers plus key": (
                HotkeyShortcut(
                    keyCode: UInt32(kVK_Space),
                    modifiers: UInt32(controlKey | optionKey)
                ),
                ["⌃", "⌥", "Space"]
            ),
            "modifier-only key keeps multi-word name intact": (
                HotkeyShortcut(keyCode: UInt32(kVK_RightOption), modifiers: 0),
                ["Right Option"]
            ),
            "plain key": (
                HotkeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0),
                ["A"]
            )
        ]

        for (name, tc) in tests {
            XCTAssertEqual(tc.shortcut.keycapLabels, tc.want, name)
        }
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

    func testCGEventFlagMappingForKeyCodes() {
        // Both physical sides of a modifier share one cumulative CGEventFlags
        // mask — this is what the event tap reads to detect a flag transition's
        // direction without the lag of CGEventSource.keyState.
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_Option)), .maskAlternate)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_RightOption)), .maskAlternate)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_Command)), .maskCommand)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_RightCommand)), .maskCommand)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_Shift)), .maskShift)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_RightShift)), .maskShift)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_Control)), .maskControl)
        XCTAssertEqual(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_RightControl)), .maskControl)
        XCTAssertNil(HotkeyShortcut.cgEventFlag(forKeyCode: UInt32(kVK_Space)))
    }

    @MainActor
    func testHotkeyShortcutClampsOutOfRangePersistedValues() throws {
        // A corrupt persisted hotkey value (negative or over UInt32.max) must
        // not crash the launch-time cast. `UInt32(clamping:)` bounds both sides;
        // the getter then re-validates and returns the (valid) clamped shortcut.
        let suiteName = "JabberTests.HotkeyShortcut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(userDefaults: defaults)

        let tests: [String: (keyCode: Int, modifiers: Int, wantKeyCode: UInt32, wantModifiers: UInt32)] = [
            "negative keyCode clamps to 0": (
                keyCode: -5,
                modifiers: Int(optionKey),
                wantKeyCode: 0,
                wantModifiers: UInt32(optionKey)
            ),
            "over-max keyCode clamps to UInt32.max": (
                keyCode: 5_000_000_000,
                modifiers: Int(optionKey),
                wantKeyCode: UInt32.max,
                wantModifiers: UInt32(optionKey)
            ),
            "negative modifiers clamps to 0": (
                keyCode: Int(kVK_RightOption),
                modifiers: -1,
                wantKeyCode: UInt32(kVK_RightOption),
                wantModifiers: 0
            ),
            "over-max modifiers clamps to UInt32.max": (
                keyCode: Int(kVK_Space),
                modifiers: 5_000_000_000,
                wantKeyCode: UInt32(kVK_Space),
                wantModifiers: UInt32.max
            )
        ]

        for (name, tc) in tests {
            defaults.set(tc.keyCode, forKey: AppSettingKey.hotkeyKeyCode)
            defaults.set(tc.modifiers, forKey: AppSettingKey.hotkeyModifiers)
            let shortcut = store.hotkeyShortcut
            XCTAssertEqual(shortcut.keyCode, tc.wantKeyCode, name)
            XCTAssertEqual(shortcut.modifiers, tc.wantModifiers, name)
        }
    }
}
