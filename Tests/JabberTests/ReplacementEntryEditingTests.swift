import XCTest
@testable import Jabber

final class ReplacementEntryEditingTests: XCTestCase {
    func testTriggersFromText() {
        let tests: [String: (input: String, want: [String])] = [
            "empty field": (input: "", want: []),
            "whitespace only": (input: "   ", want: []),
            "commas only": (input: " , ,, ", want: []),
            "single trigger": (input: "troy", want: ["troy"]),
            "comma separated with uneven spacing": (input: "troy, abed ,annie", want: ["troy", "abed", "annie"]),
            "trailing comma while typing the next trigger": (input: "troy, ", want: ["troy"]),
            "empty pieces between commas are dropped": (input: "troy,, ,abed", want: ["troy", "abed"]),
            "multi-word triggers keep inner spaces": (
                input: "señor chang, greendale community college",
                want: ["señor chang", "greendale community college"]
            ),
            "pasted tabs and newlines are trimmed": (input: "\ttroy\n,\nabed ", want: ["troy", "abed"]),
            "case is preserved": (input: "Troy Barnes", want: ["Troy Barnes"])
        ]

        for (name, tc) in tests {
            XCTAssertEqual(ReplacementEntryEditing.triggers(from: tc.input), tc.want, name)
        }
    }

    func testTriggerTextRoundTripsThroughParsing() {
        let tests: [String: (input: [String], want: String)] = [
            "no triggers": (input: [], want: ""),
            "single trigger": (input: ["troy"], want: "troy"),
            "several triggers": (input: ["troy", "señor chang"], want: "troy, señor chang")
        ]

        for (name, tc) in tests {
            let text = ReplacementEntryEditing.triggerText(from: tc.input)
            XCTAssertEqual(text, tc.want, name)
            XCTAssertEqual(ReplacementEntryEditing.triggers(from: text), tc.input, name)
        }
    }

    func testEntriesToPersistDropsOnlyBlankRows() {
        let complete = ReplacementEntry(triggers: ["greendale", "greendale cc"], replacement: "Greendale Community College")
        let triggersOnly = ReplacementEntry(triggers: ["troy"], replacement: "")
        let replacementOnly = ReplacementEntry(triggers: [], replacement: "Abed Nadir")
        let untrimmed = ReplacementEntry(triggers: [" chang "], replacement: " Señor Chang ")
        let blank = ReplacementEntry(triggers: [], replacement: "")
        let whitespaceOnly = ReplacementEntry(triggers: ["", "  "], replacement: " \n")

        let tests: [String: (input: [ReplacementEntry], want: [ReplacementEntry])] = [
            "no entries": (input: [], want: []),
            "complete rule is kept": (input: [complete], want: [complete]),
            "blank row is dropped": (input: [blank], want: []),
            "whitespace-only row is dropped": (input: [whitespaceOnly], want: []),
            "triggers without a replacement are kept as in-progress work": (
                input: [triggersOnly], want: [triggersOnly]
            ),
            "replacement without triggers is kept as in-progress work": (
                input: [replacementOnly], want: [replacementOnly]
            ),
            "kept rows are stored exactly as entered": (input: [untrimmed], want: [untrimmed]),
            "ids and order survive around dropped rows": (
                input: [blank, complete, whitespaceOnly, triggersOnly, blank, replacementOnly],
                want: [complete, triggersOnly, replacementOnly]
            )
        ]

        for (name, tc) in tests {
            XCTAssertEqual(ReplacementEntryEditing.entriesToPersist(tc.input), tc.want, name)
        }
    }
}
