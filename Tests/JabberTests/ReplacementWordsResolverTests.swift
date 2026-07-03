import XCTest
@testable import Jabber

final class ReplacementWordsResolverTests: XCTestCase {
    func testNoEntriesReturnsTranscriptUnchanged() {
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy and abed", entries: []),
            "troy and abed"
        )
    }

    func testCaseInsensitiveLiteralReplacement() {
        let entries = [ReplacementEntry(triggers: ["troy"], replacement: "Troy Barnes")]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "I saw TROY and troy and Troy", entries: entries),
            "I saw Troy Barnes and Troy Barnes and Troy Barnes"
        )
    }

    func testPunctuationAdjacencyMatches() {
        let entries = [ReplacementEntry(triggers: ["troy"], replacement: "Troy")]
        // Trigger sits next to comma, period, parentheses — all should match.
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "(troy), troy. troy!", entries: entries),
            "(Troy), Troy. Troy!"
        )
    }

    func testWholeWordBoundaryRejectsSubstringOfLargerWord() {
        let entries = [ReplacementEntry(triggers: ["troy"], replacement: "Troy")]
        // "troy" must NOT match inside "TroyBarnes" or "GreendaleTroy".
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "TroyBarnes and GreendaleTroy and troy", entries: entries),
            "TroyBarnes and GreendaleTroy and Troy"
        )
    }

    func testMultiWordTrigger() {
        let entries = [ReplacementEntry(triggers: ["señor chang"], replacement: "Señor Chang")]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "hello señor chang welcome", entries: entries),
            "hello Señor Chang welcome"
        )
    }

    func testMultiWordTriggerBoundaryRejectsPartialOverlap() {
        let entries = [ReplacementEntry(triggers: ["señor chang"], replacement: "Señor Chang")]
        // "señor chang" should not match inside "señor changnesia".
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "welcome to señor changnesia", entries: entries),
            "welcome to señor changnesia"
        )
    }

    func testLongestTriggerWinsAtSamePosition() {
        // "troy barnes" and "troy" both match at the start; longest wins.
        let entries = [
            ReplacementEntry(triggers: ["troy"], replacement: "Troy"),
            ReplacementEntry(triggers: ["troy barnes"], replacement: "Troy Barnes")
        ]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy barnes is here", entries: entries),
            "Troy Barnes is here"
        )
    }

    func testReplacementsDoNotChain() {
        // "troy" -> "abed" and "abed" -> "annie". A replaced span must not be
        // re-scanned, so we never end up with "annie".
        let entries = [
            ReplacementEntry(triggers: ["troy"], replacement: "abed"),
            ReplacementEntry(triggers: ["abed"], replacement: "annie")
        ]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy at greendale", entries: entries),
            "abed at greendale"
        )
    }

    func testReplacementOutputIsLiteral() {
        // Replacement is typed verbatim, preserving case/punctuation.
        let entries = [ReplacementEntry(triggers: ["greendale"], replacement: "GREENDALE!!")]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "greendale rules", entries: entries),
            "GREENDALE!! rules"
        )
    }

    func testEmptyTriggersAndReplacementsAreIgnored() {
        let entries = [
            ReplacementEntry(triggers: ["", "  "], replacement: "ShouldNotApply"),
            ReplacementEntry(triggers: ["troy"], replacement: ""),
            ReplacementEntry(triggers: ["abed"], replacement: "Abed")
        ]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy and abed", entries: entries),
            "troy and Abed"
        )
    }

    func testDuplicateTriggersCollapseToFirstReplacement() {
        // First-defined replacement wins for a duplicate trigger (case-
        // insensitive). Order/conflict is predictable and tested.
        let entries = [
            ReplacementEntry(triggers: ["troy", "TROY"], replacement: "First"),
            ReplacementEntry(triggers: ["troy"], replacement: "Second")
        ]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy", entries: entries),
            "First"
        )
    }

    func testMultipleTriggersWithinOneEntryAllMapToSameReplacement() {
        let entries = [ReplacementEntry(triggers: ["troy", "abed", "annie"], replacement: "Human Being")]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy met abed and annie", entries: entries),
            "Human Being met Human Being and Human Being"
        )
    }

    func testLeftToRightSinglePassDoesNotReconsiderEarlierPositions() {
        // After replacing at position 0, the scan resumes AFTER the matched
        // span. An earlier trigger that would now match the replacement text
        // is never revisited.
        let entries = [
            ReplacementEntry(triggers: ["ab"], replacement: "abab"),
            ReplacementEntry(triggers: ["abab"], replacement: "X")
        ]
        // "ab" -> "abab"; the "abab" rule does not fire on the emitted text.
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "ab cd", entries: entries),
            "abab cd"
        )
    }

    func testTriggerAtStartAndEndOfString() {
        let entries = [ReplacementEntry(triggers: ["troy"], replacement: "Troy")]
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy", entries: entries),
            "Troy"
        )
        // String boundaries count as word boundaries.
        XCTAssertEqual(
            ReplacementWordsResolver.resolve(transcript: "troy troy", entries: entries),
            "Troy Troy"
        )
    }

    // MARK: - Codec

    func testCodecEmptyRoundTrip() {
        XCTAssertEqual(ReplacementEntriesCodec.encode([]), "")
        XCTAssertEqual(ReplacementEntriesCodec.decode(""), [])
        XCTAssertEqual(ReplacementEntriesCodec.decode("   "), [])
    }

    func testCodecRoundTripPreservesEntries() throws {
        let entries = try [
            ReplacementEntry(id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), triggers: ["troy", "abed"], replacement: "Troy Barnes"),
            ReplacementEntry(id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")), triggers: ["señor chang"], replacement: "Señor Chang")
        ]
        let encoded = ReplacementEntriesCodec.encode(entries)
        let decoded = ReplacementEntriesCodec.decode(encoded)
        XCTAssertEqual(decoded, entries)
    }

    func testCodecDecodeCorruptJSONReturnsEmpty() {
        // Corrupt JSON must not throw or crash; it recovers to an empty list.
        XCTAssertEqual(ReplacementEntriesCodec.decode("{not json"), [])
        XCTAssertEqual(ReplacementEntriesCodec.decode("\"just a string\""), [])
    }
}
