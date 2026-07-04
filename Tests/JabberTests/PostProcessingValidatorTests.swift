import XCTest
@testable import Jabber

final class PostProcessingValidatorTests: XCTestCase {
    // MARK: - suspiciousPostProcessingError integration

    func testCleanPassesValidation() {
        let raw = "hello world this is a test transcript with enough words"
        let processed = "Hello world, this is a test transcript with enough words."
        XCTAssertNil(PostProcessingValidator.suspiciousPostProcessingError(raw: raw, processed: processed))
    }

    // MARK: - Shrinkage heuristic

    func testShrinkageBelowMinimumRawWordsDoesNotTrigger() {
        let raw = "one two three four"
        let processed = "one two"
        XCTAssertNil(PostProcessingValidator.suspiciousShrinkageError(raw: raw, processed: processed))
    }

    func testShrinkageAtExactMinimumRawWordsTriggers() {
        let raw = (1 ... 8).map { "word\($0)" }.joined(separator: " ")
        let processed = "word1 word2"
        let error = PostProcessingValidator.suspiciousShrinkageError(raw: raw, processed: processed)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.kind, .suspiciousShrinkage)
    }

    func testShrinkageAtExactRatioDoesNotTrigger() {
        let raw = (1 ... 8).map { "word\($0)" }.joined(separator: " ")
        let processed = (1 ... 4).map { "word\($0)" }.joined(separator: " ")
        XCTAssertNil(PostProcessingValidator.suspiciousShrinkageError(raw: raw, processed: processed))
    }

    func testShrinkageSuppressedByCorrectionTrigger() {
        let tests: [(name: String, phrase: String)] = [
            ("scratchThat", "scratch that"),
            ("deleteThat", "delete that"),
            ("neverMind", "never mind"),
            ("cancel", "cancel"),
            ("actually", "actually"),
            ("noWait", "no wait"),
            ("waitWait", "wait wait"),
            ("oops", "oops"),
            ("sorry", "sorry")
        ]

        for tc in tests {
            let raw = "word1 word2 word3 word4 word5 word6 word7 \(tc.phrase) word8"
            let processed = "word8"
            XCTAssertNil(
                PostProcessingValidator.suspiciousShrinkageError(raw: raw, processed: processed),
                "Shrinkage should be suppressed by correction trigger '\(tc.phrase)'"
            )
        }
    }

    func testShrinkageNotSuppressedBySubstringOfTrigger() {
        // "factually" contains "actually" as a substring but is not a correction.
        let raw = (1 ... 7).map { "word\($0)" }.joined(separator: " ") + " factually"
        let processed = "word1"
        let error = PostProcessingValidator.suspiciousShrinkageError(raw: raw, processed: processed)
        XCTAssertNotNil(error, "Shrinkage should NOT be suppressed by 'factually' (substring of 'actually')")
        XCTAssertEqual(error?.kind, .suspiciousShrinkage)
    }

    // MARK: - Rogue markdown detection

    func testRogueMarkdownRejectsAtxHeading() {
        let raw = "hello world this is a test"
        let processed = "# Hello World"
        let error = PostProcessingValidator.rogueMarkdownError(raw: raw, processed: processed)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.kind, .rogueMarkdown)
    }

    func testRogueMarkdownRejectsBulletList() {
        let bullets = ["- item", "* item", "+ item"]
        for processed in bullets {
            let error = PostProcessingValidator.rogueMarkdownError(
                raw: "this is a test transcript",
                processed: processed
            )
            XCTAssertNotNil(error, "Should reject bullet list: \(processed)")
            XCTAssertEqual(error?.kind, .rogueMarkdown)
        }
    }

    func testRogueMarkdownRejectsOrderedList() {
        let ordered = ["1. first", "42. answer"]
        for processed in ordered {
            let error = PostProcessingValidator.rogueMarkdownError(
                raw: "this is a test transcript",
                processed: processed
            )
            XCTAssertNotNil(error, "Should reject ordered list: \(processed)")
            XCTAssertEqual(error?.kind, .rogueMarkdown)
        }
    }

    func testRogueMarkdownAllowsPlainProse() {
        let raw = "hello world this is a test"
        let processed = "Hello world, this is a test."
        XCTAssertNil(PostProcessingValidator.rogueMarkdownError(raw: raw, processed: processed))
    }

    func testRogueMarkdownDoesNotTriggerOnNumberInSentence() {
        let raw = "the answer is forty two"
        let processed = "The answer is 42."
        XCTAssertNil(PostProcessingValidator.rogueMarkdownError(raw: raw, processed: processed))
    }

    // MARK: - Formatting command suppression

    func testFormattingCommandSuppressesMarkdownRejection() {
        let words = PostProcessingValidator.formattingCommandWords
        for word in words {
            let raw = "make this a \(word) please"
            let processed = "# Formatted Text"
            XCTAssertNil(
                PostProcessingValidator.rogueMarkdownError(raw: raw, processed: processed),
                "Markdown should be allowed when raw contains formatting command '\(word)'"
            )
        }
    }

    // MARK: - beginsWithMarkdownStructure edge cases

    func testBeginsWithMarkdownStructureEdgeCases() {
        let tests: [(input: String, expected: Bool)] = [
            ("# heading", true),
            ("## subheading", true),
            ("- bullet", true),
            ("* bullet", true),
            ("+ bullet", true),
            ("1. ordered", true),
            ("42. ordered", true),
            ("plain text", false),
            ("42", false),
            ("42.", true),
            ("#", true),
            ("-", false),
            ("", false),
            ("\n\n# heading after blanks", true)
        ]

        for tc in tests {
            XCTAssertEqual(
                PostProcessingValidator.beginsWithMarkdownStructure(tc.input),
                tc.expected,
                "beginsWithMarkdownStructure(\"\(tc.input)\")"
            )
        }
    }

    // MARK: - containsCorrectionTrigger word boundary

    func testContainsCorrectionTriggerWordBoundary() {
        XCTAssertTrue(PostProcessingValidator.containsCorrectionTrigger("oops I did it again"))
        XCTAssertTrue(PostProcessingValidator.containsCorrectionTrigger("OOPS"))
        XCTAssertTrue(PostProcessingValidator.containsCorrectionTrigger("...cancel..."))
        XCTAssertTrue(PostProcessingValidator.containsCorrectionTrigger("well, sorry, I forgot"))
        XCTAssertTrue(PostProcessingValidator.containsCorrectionTrigger("scratch that last part"))
    }

    func testContainsCorrectionTriggerRejectsSubstringMatches() {
        XCTAssertFalse(PostProcessingValidator.containsCorrectionTrigger("factually correct"))
        XCTAssertFalse(PostProcessingValidator.containsCorrectionTrigger("cancelled the flight"))
        XCTAssertFalse(PostProcessingValidator.containsCorrectionTrigger("sorrowful"))
    }

    // MARK: - wordCount

    func testWordCount() {
        XCTAssertEqual(PostProcessingValidator.wordCount(""), 0)
        XCTAssertEqual(PostProcessingValidator.wordCount("one"), 1)
        XCTAssertEqual(PostProcessingValidator.wordCount("one two three"), 3)
        XCTAssertEqual(PostProcessingValidator.wordCount("  one  two  "), 2)
        XCTAssertEqual(PostProcessingValidator.wordCount("one\ntwo\tthree"), 3)
    }
}
