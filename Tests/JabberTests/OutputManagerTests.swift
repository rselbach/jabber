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
}
