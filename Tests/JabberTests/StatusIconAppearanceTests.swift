import AppKit
import XCTest
@testable import Jabber

@MainActor
final class StatusIconAppearanceTests: XCTestCase {
    func testEachStateHasDistinctSymbolAndSpokenDescription() {
        let cases: [String: (state: AppDelegate.AppState, wantSymbol: String, wantDescription: String)] = [
            "downloading": (.downloading, "arrow.down.circle", "Jabber, preparing speech model"),
            "ready": (.ready, "waveform", "Jabber, ready to dictate"),
            "recording": (.recording, "waveform.circle.fill", "Jabber, recording"),
            "transcribing": (.transcribing, "ellipsis.circle", "Jabber, transcribing"),
            "error": (.error, "exclamationmark.triangle", "Jabber, model unavailable")
        ]

        for (name, tc) in cases {
            XCTAssertEqual(tc.state.symbolName, tc.wantSymbol, name)
            XCTAssertEqual(tc.state.accessibilityDescription, tc.wantDescription, name)
            XCTAssertNotNil(
                NSImage(systemSymbolName: tc.state.symbolName, accessibilityDescription: tc.state.accessibilityDescription),
                "\(name): SF Symbol must exist"
            )
        }
    }

    func testVoiceOverHearsDownloadProgress() {
        let cases: [String: (state: AppDelegate.AppState, progress: Double?, want: String)] = [
            "downloading with known progress": (.downloading, 0.426, "Jabber, preparing speech model, 42 percent"),
            "downloading without progress": (.downloading, nil, "Jabber, preparing speech model"),
            "progress ignored outside downloads": (.recording, 0.5, "Jabber, recording")
        ]

        for (name, tc) in cases {
            XCTAssertEqual(tc.state.accessibilityDescription(progress: tc.progress), tc.want, name)
        }
    }

    func testDownloadProgressIconIsATemplateWithItsDescription() {
        let image = DownloadProgressIcon.image(progress: 0.5, accessibilityDescription: "Jabber, preparing speech model, 50 percent")

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, DownloadProgressIcon.size)
        XCTAssertEqual(image.accessibilityDescription, "Jabber, preparing speech model, 50 percent")
    }
}
