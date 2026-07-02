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
        // 19 UTF-16 units of ASCII puts the emoji's surrogate pair exactly on the
        // 20-unit chunk boundary, exercising the pull-back logic.
        let text = String(repeating: "a", count: 19) + "🎤"
        let chunks = TypingService.unicodeChunks(for: text)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 19)
        XCTAssertEqual(chunks[1], Array("🎤".utf16))
    }

    func testUnicodeChunksNeverExceedUTF16CapForMixedEmojiString() {
        // Long string mixing ASCII, multi-code-unit emoji, and a ZWJ family
        // sequence (Community-style: "Streets ahead"). No chunk may exceed the
        // 20 UTF-16 unit CGEvent cap, and reassembling the chunks must reproduce
        // the original UTF-16 exactly (i.e. no surrogate pair was split).
        let unit = "Streets ahead 🎤🎬👨‍👩‍👧 "
        let text = String(repeating: unit, count: 30)

        let chunks = TypingService.unicodeChunks(for: text)
        XCTAssertFalse(chunks.isEmpty)

        let cap = 20
        for chunk in chunks {
            XCTAssertLessThanOrEqual(
                chunk.count,
                cap,
                "Chunk of \(chunk.count) UTF-16 units exceeds the \(cap)-unit CGEvent cap"
            )
        }

        let reassembled = chunks.flatMap { $0 }
        XCTAssertEqual(reassembled, Array(text.utf16))
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
