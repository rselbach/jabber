import AppKit
import XCTest
@testable import Jabber

@MainActor
final class OutputManagerTests: XCTestCase {
    func testShouldAttemptPasteReturnsTrueForPasteModeWithClipboardSuccess() {
        XCTAssertTrue(
            OutputManager.shouldAttemptPaste(
                mode: .pasteInPlace,
                didCopyToClipboard: true
            )
        )
    }

    func testShouldAttemptPasteReturnsFalseForPasteModeWithClipboardFailure() {
        XCTAssertFalse(
            OutputManager.shouldAttemptPaste(
                mode: .pasteInPlace,
                didCopyToClipboard: false
            )
        )
    }

    func testShouldAttemptPasteReturnsFalseForClipboardModeWithClipboardSuccess() {
        XCTAssertFalse(
            OutputManager.shouldAttemptPaste(
                mode: .clipboard,
                didCopyToClipboard: true
            )
        )
    }

    func testRequiresAccessibilityPermissionOnlyForPasteMode() {
        XCTAssertTrue(OutputManager.requiresAccessibilityPermission(mode: .pasteInPlace))
        XCTAssertFalse(OutputManager.requiresAccessibilityPermission(mode: .clipboard))
    }

    func testPasteboardSnapshotRestoresStringContents() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Troy Barnes", forType: .string))
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Abed Nadir", forType: .string))

        XCTAssertTrue(snapshot.restore(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Troy Barnes")
    }

    func testPasteboardSnapshotRestoresEmptyClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertTrue(pasteboard.setString("Señor Chang", forType: .string))

        XCTAssertTrue(snapshot.restore(to: pasteboard))
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
