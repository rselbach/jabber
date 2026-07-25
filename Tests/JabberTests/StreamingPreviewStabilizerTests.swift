import XCTest
@testable import Jabber

final class StreamingPreviewStabilizerTests: XCTestCase {
    func testFirstDecodeIsShownVerbatim() {
        var stabilizer = StreamingPreviewStabilizer()

        XCTAssertEqual(stabilizer.stabilize("troy"), "troy")
    }

    func testUnsettledTailKeepsMovingUntilTwoDecodesAgree() {
        var stabilizer = StreamingPreviewStabilizer()

        XCTAssertEqual(stabilizer.stabilize("troy bahnes"), "troy bahnes")
        // "troy" is now agreed on, so only the tail is free to change.
        XCTAssertEqual(stabilizer.stabilize("troy barnes"), "troy barnes")
        XCTAssertEqual(stabilizer.stabilize("troy barnes enrolled"), "troy barnes enrolled")
    }

    func testCommittedPrefixSurvivesALaterRevision() {
        var stabilizer = StreamingPreviewStabilizer()

        _ = stabilizer.stabilize("troy barnes")
        _ = stabilizer.stabilize("troy barnes enrolled")
        // Both passes agreed on "troy barnes", so a third pass cannot rewrite it.
        XCTAssertEqual(stabilizer.stabilize("troy burns enrolled at"), "troy barnes enrolled at")
    }

    func testAgreementIgnoresCaseAndPunctuation() {
        var stabilizer = StreamingPreviewStabilizer()

        _ = stabilizer.stabilize("troy and abed")
        XCTAssertEqual(stabilizer.stabilize("Troy, and abed in"), "troy and abed in")
    }

    func testShorterDecodeKeepsTheCommittedText() {
        var stabilizer = StreamingPreviewStabilizer()

        _ = stabilizer.stabilize("troy and abed")
        _ = stabilizer.stabilize("troy and abed in")
        XCTAssertEqual(stabilizer.stabilize("troy"), "troy and abed")
    }

    func testEmptyDecodeDoesNotBlankThePreview() {
        var stabilizer = StreamingPreviewStabilizer()

        _ = stabilizer.stabilize("troy and")
        _ = stabilizer.stabilize("troy and abed")
        XCTAssertEqual(stabilizer.stabilize(""), "troy and")
    }

    func testResetClearsCommittedText() {
        var stabilizer = StreamingPreviewStabilizer()

        _ = stabilizer.stabilize("troy and abed")
        _ = stabilizer.stabilize("troy and abed")
        stabilizer.reset()

        XCTAssertEqual(stabilizer.stabilize("greendale"), "greendale")
    }
}
