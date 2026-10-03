import XCTest
@testable import Jabber

@MainActor
final class PostProcessingFailureMessageTests: XCTestCase {
    func testMessageNamesWhereTheRawTranscriptWent() {
        let cases: [String: (outputMode: TypingService.OutputMode, want: String)] = [
            "clipboard": (
                .clipboard,
                "OpenRouter cleanup failed (Greendale is offline). Copied the raw transcript to the clipboard instead."
            ),
            "direct typing": (
                .directTyping,
                "OpenRouter cleanup failed (Greendale is offline). Typed the raw transcript instead."
            )
        ]

        for (name, tc) in cases {
            let got = AppDelegate.postProcessingFailureMessage(
                providerName: "OpenRouter",
                errorDescription: "Greendale is offline",
                outputMode: tc.outputMode
            )
            XCTAssertEqual(got, tc.want, name)
        }
    }
}
