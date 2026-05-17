import XCTest
@testable import Jabber

final class TranscriptionActivityTrackerTests: XCTestCase {
    func testStartMarksTranscriptionActive() {
        let id = UUID()
        var tracker = TranscriptionActivityTracker()

        XCTAssertTrue(tracker.start(id))
        XCTAssertTrue(tracker.isActive)
        XCTAssertEqual(tracker.activeID, id)
    }

    func testStartReturnsFalseWhenTranscriptionAlreadyActive() {
        let firstID = UUID()
        let secondID = UUID()
        var tracker = TranscriptionActivityTracker()

        XCTAssertTrue(tracker.start(firstID))
        XCTAssertFalse(tracker.start(secondID))
        XCTAssertEqual(tracker.activeID, firstID)
    }

    func testCompleteClearsMatchingTranscription() {
        let id = UUID()
        var tracker = TranscriptionActivityTracker()
        XCTAssertTrue(tracker.start(id))

        XCTAssertTrue(tracker.complete(id))
        XCTAssertFalse(tracker.isActive)
        XCTAssertNil(tracker.activeID)
    }

    func testCompleteIgnoresStaleTranscription() {
        let activeID = UUID()
        let staleID = UUID()
        var tracker = TranscriptionActivityTracker()
        XCTAssertTrue(tracker.start(activeID))

        XCTAssertFalse(tracker.complete(staleID))
        XCTAssertTrue(tracker.isActive)
        XCTAssertEqual(tracker.activeID, activeID)
    }
}
