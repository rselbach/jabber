import Carbon
import XCTest
@testable import Jabber

final class HotkeyRecorderReducerTests: XCTestCase {
    // MARK: - Modifier-only (lone modifier press + release)

    func testSoloRightOptionPressThenReleaseCommitsModifierOnly() {
        var r = HotkeyRecorderReducer()

        // Right Option pressed on its own: armed, not committed.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: UInt32(optionKey)), .wait)
        XCTAssertEqual(r.pendingModifierKeyCode, UInt32(kVK_RightOption))

        // Released with nothing else held: commit modifier-only.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: 0), .commitModifierOnly(keyCode: UInt32(kVK_RightOption)))
        XCTAssertNil(r.pendingModifierKeyCode)
    }

    func testSoloLeftOptionPressThenReleaseCommitsLeftOption() {
        var r = HotkeyRecorderReducer()

        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_Option), heldModifiers: UInt32(optionKey)), .wait)
        XCTAssertEqual(r.pendingModifierKeyCode, UInt32(kVK_Option))
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_Option), heldModifiers: 0), .commitModifierOnly(keyCode: UInt32(kVK_Option)))
    }

    // MARK: - The regression: modifier + key must record the combo

    func testLeftOptionThenSpaceRecordsOptionSpaceCombo() {
        // Reproduces the bug where Left Option alone was recorded immediately,
        // making Option+Space impossible to set.
        var r = HotkeyRecorderReducer()

        // Left Option pressed on its own arms the candidate but does NOT commit.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_Option), heldModifiers: UInt32(optionKey)), .wait)

        // Space pressed while Left Option held: combo using current flags.
        let outcome = r.keyDown(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), isEscape: false)
        XCTAssertEqual(outcome, .commitCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)))
        XCTAssertNil(r.pendingModifierKeyCode, "pending modifier-only candidate must be cleared once a combo key arrives")
    }

    func testRightCommandThenERecordsCommandECombo() {
        var r = HotkeyRecorderReducer()

        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightCommand), heldModifiers: UInt32(cmdKey)), .wait)
        XCTAssertEqual(
            r.keyDown(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey), isEscape: false),
            .commitCombo(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey))
        )
    }

    // MARK: - Escape

    func testEscapeWhileModifierPendingCancels() {
        var r = HotkeyRecorderReducer()
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: UInt32(optionKey)), .wait)

        XCTAssertEqual(r.keyDown(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey), isEscape: true), .cancel)
        XCTAssertNil(r.pendingModifierKeyCode)
    }

    func testEscapeWithNoModifierCancels() {
        var r = HotkeyRecorderReducer()
        XCTAssertEqual(r.keyDown(keyCode: UInt32(kVK_Escape), modifiers: 0, isEscape: true), .cancel)
    }

    // MARK: - Combo without a required modifier (validation happens in the view)

    func testBareKeyDownProducesComboOutcomeForViewToValidate() {
        // A plain "A" with no modifier yields a combo outcome; the view runs
        // HotkeyShortcut.validationError to reject it (missing required modifier).
        var r = HotkeyRecorderReducer()
        XCTAssertEqual(
            r.keyDown(keyCode: UInt32(kVK_ANSI_A), modifiers: 0, isEscape: false),
            .commitCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
        )
    }

    // MARK: - Stacked modifiers are not mistaken for modifier-only

    func testSecondModifierWhilePendingDoesNotCommitModifierOnlyOnRelease() {
        // Right Option armed, then Command also pressed. The release path must
        // not commit Right Option as modifier-only because Command is held.
        var r = HotkeyRecorderReducer()
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: UInt32(optionKey)), .wait)

        // Command pressed while Option held: heldModifiers != cmdKey, so it is
        // not armed as a new candidate; existing Option candidate stays.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightCommand), heldModifiers: UInt32(optionKey | cmdKey)), .wait)

        // Releasing Command: still Option held, so heldModifiers != 0 -> no commit.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightCommand), heldModifiers: UInt32(optionKey)), .wait)
    }

    func testNonModifierFlagChangeIsIgnored() {
        // A flags-changed for a non-modifier key (e.g. Caps Lock) must not arm
        // or commit anything.
        var r = HotkeyRecorderReducer()
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_CapsLock), heldModifiers: 0), .wait)
        XCTAssertNil(r.pendingModifierKeyCode)
    }

    func testReleaseWithoutArmedCandidateWaits() {
        var r = HotkeyRecorderReducer()
        // Release arriving with no prior press: nothing to commit.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: 0), .wait)
    }

    // MARK: - Reset

    func testResetClearsPendingCandidate() {
        var r = HotkeyRecorderReducer()
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: UInt32(optionKey)), .wait)
        XCTAssertNotNil(r.pendingModifierKeyCode)

        r.reset()
        XCTAssertNil(r.pendingModifierKeyCode)

        // After reset, a lone release must not commit a stale candidate.
        XCTAssertEqual(r.flagsChanged(keyCode: UInt32(kVK_RightOption), heldModifiers: 0), .wait)
    }
}
