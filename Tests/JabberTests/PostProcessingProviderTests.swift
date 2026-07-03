import XCTest
@testable import Jabber

/// Prompt-content guardrails for `AppleIntelligencePostProcessor`.
///
/// These tests never invoke Apple Intelligence; they only assert that the
/// hidden system prompt forbids summarizing/restructuring dictation and that
/// the old structure-inventing example (`# Shopping`) is gone. They protect
/// against regressions where a prompt tweak reintroduces the bug where
/// post-processing rewrote a faithful transcript into a short summary.
final class PostProcessingProviderTests: XCTestCase {
    private var prompt: String {
        AppleIntelligencePostProcessor.instructions
    }

    // MARK: - Preservation guardrails (highest priority)

    func testPromptForbidsSummarizing() {
        XCTAssertTrue(
            prompt.contains("Do NOT summarize"),
            "Prompt must explicitly forbid summarizing."
        )
    }

    func testPromptForbidsParaphrasing() {
        XCTAssertTrue(
            prompt.contains("Do NOT paraphrase"),
            "Prompt must explicitly forbid paraphrasing."
        )
    }

    func testPromptForbidsShorteningAndRewritingAndOmission() {
        XCTAssertTrue(
            prompt.contains("Do NOT shorten"),
            "Prompt must forbid shortening."
        )
        XCTAssertTrue(
            prompt.contains("Do NOT rewrite"),
            "Prompt must forbid rewriting."
        )
        XCTAssertTrue(
            prompt.contains("Do NOT omit semantic content"),
            "Prompt must forbid omitting semantic content."
        )
    }

    func testPromptCleansDeliveryNotContent() {
        XCTAssertTrue(
            prompt.contains("clean DELIVERY, never CONTENT"),
            "Prompt must state it cleans delivery, never content."
        )
    }

    func testPromptPreservesEveryNonFillerWordInOrder() {
        XCTAssertTrue(
            prompt.contains("PRESERVE every non-filler word"),
            "Prompt must require preserving every non-filler word in order."
        )
    }

    // MARK: - Structure-invention ban

    func testPromptNeverCreatesStructure() {
        XCTAssertTrue(
            prompt.contains("NEVER create structure"),
            "Prompt must forbid inventing structure the user did not dictate."
        )
    }

    func testPromptBansMarkdownUnlessCommanded() {
        XCTAssertTrue(
            prompt.contains("Do NOT invent headings"),
            "Prompt must forbid inventing headings/lists/bold/markdown."
        )
    }

    func testPromptTreatsAmbiguousCommandsAsLiteralText() {
        XCTAssertTrue(
            prompt.contains("treat it as LITERAL dictated text"),
            "Prompt must tell the model to treat ambiguous commands as literal text."
        )
    }

    // MARK: - Removed bad example

    func testPromptDoesNotContainShoppingHeaderExample() {
        XCTAssertFalse(
            prompt.contains("# Shopping"),
            "The `# Shopping` structure-inventing example must be removed."
        )
    }

    // MARK: - Useful dictation cleanup still present

    func testPromptHandlesNewlineAsLineBreakCommand() {
        XCTAssertTrue(
            prompt.contains("\"newline\""),
            "Prompt must treat standalone newline as a line-break command."
        )
    }

    func testPromptKeepsCoreDictationCapabilities() {
        XCTAssertTrue(prompt.contains("EXECUTE commands"))
        XCTAssertTrue(prompt.contains("scratch that"))
        XCTAssertTrue(prompt.contains("smiley face"))
        XCTAssertTrue(prompt.contains("EXPAND abbreviations"))
        XCTAssertTrue(prompt.contains("CONVERT numbers"))
    }
}
