import XCTest
@testable import Jabber

final class DictationJoinerTests: XCTestCase {
    func testJoin() {
        let tests: [String: (preceding: String, text: String, want: String)] = [
            "start of field": ("", "hello there.", "hello there."),
            "after a sentence": ("Done.", "Next thing.", " Next thing."),
            "after a sentence lowercased": ("Done.", "next thing.", " Next thing."),
            "after a question": ("Ready?", "yes.", " Yes."),
            "after a space": ("Done. ", "next thing.", "Next thing."),
            "after a newline": ("Dear Troy,\n", "thanks for", "Thanks for"),
            "mid-sentence continuation word": ("I tried it", "And it worked.", " and it worked."),
            "mid-sentence other word": ("I asked", "Troy Barnes.", " Troy Barnes."),
            "after a comma": ("Well,", "The plan works.", " the plan works."),
            "after a closing quote": ("He said \"go.\"", "then left.", " Then left."),
            "after an opening paren": ("See (", "Greendale", "Greendale"),
            "before punctuation": ("Troy", ", Abed", ", Abed"),
            "contraction is not a continuation word": ("Well", "It's fine.", " It's fine."),
            "word that only starts like one": ("We met", "Andre.", " Andre."),
            "empty text": ("Done.", "", "")
        ]
        for (name, tc) in tests {
            XCTAssertEqual(DictationJoiner.join(tc.text, after: tc.preceding), tc.want, name)
        }
    }
}
