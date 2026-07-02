import AppKit
import XCTest
@testable import Jabber

@MainActor
final class TypingServiceTests: XCTestCase {
    func testRequiresAccessibilityPermissionOnlyForDirectTypingMode() {
        XCTAssertTrue(TypingService.requiresAccessibilityPermission(mode: .directTyping))
        XCTAssertFalse(TypingService.requiresAccessibilityPermission(mode: .clipboard))
    }

    func testMigratesLegacyPasteModeToDirectTyping() {
        XCTAssertEqual(
            TypingService.migratedOutputModeRawValue("paste"),
            TypingService.OutputMode.directTyping.rawValue
        )
    }

    func testKeepsClipboardModeDuringMigration() {
        XCTAssertEqual(
            TypingService.migratedOutputModeRawValue("clipboard"),
            TypingService.OutputMode.clipboard.rawValue
        )
    }

    func testUnknownOutputModeFallsBackToDirectTyping() {
        XCTAssertEqual(
            TypingService.migratedOutputModeRawValue("troy-and-abed-in-the-mode"),
            TypingService.OutputMode.directTyping.rawValue
        )
    }

    func testUnicodeChunksDoNotSplitSurrogatePairsAtChunkBoundary() {
        let text = String(repeating: "a", count: 199) + "🎤"
        let chunks = TypingService.unicodeChunks(for: text)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 199)
        XCTAssertEqual(chunks[1], Array("🎤".utf16))
    }

    func testAppIconReturnsImageForValidProcessID() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let icon = TypingService.appIcon(forTargetProcessID: pid)
        XCTAssertNotNil(icon)
    }

    func testAppIconForNilOrInvalidProcessIDDoesNotCrash() {
        XCTAssertNoThrow(TypingService.appIcon(forTargetProcessID: nil))
        XCTAssertNoThrow(TypingService.appIcon(forTargetProcessID: pid_t(999_999)))
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
