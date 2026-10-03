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
}
