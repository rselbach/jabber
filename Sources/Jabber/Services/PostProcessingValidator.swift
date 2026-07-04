import Foundation

/// Pure post-processing validation. Extracted from `DictationCoordinator` so
/// the guardrail logic (shrinkage heuristic, rogue markdown detection, correction
/// trigger suppression) is unit-testable without running the full coordinator.
///
/// `DictationCoordinator` calls `suspiciousPostProcessingError(raw:processed:)`
/// after each post-processing pass. A non-nil result means the provider output
/// looks wrong and should be retried or rejected in favor of the raw transcript.
enum PostProcessingValidator {
    /// Words the user can speak to explicitly request markdown/formatting in
    /// the output. When any of these appear in the raw transcript, markdown in
    /// the processed result is treated as intentional and is NOT rejected.
    static let formattingCommandWords: Set<String> = [
        "header", "heading", "headings",
        "bullet", "bullets",
        "list", "lists",
        "bold",
        "italics", "italic",
        "underline", "underlines",
        "title", "titles",
        "numbered"
    ]

    /// Self-correction phrases that legitimately shrink the output (everything
    /// before the trigger is discarded). When any of these appear in the raw
    /// transcript the aggressive-shrinkage heuristic is skipped.
    static let correctionTriggerPhrases: [String] = [
        "scratch that", "delete that", "never mind",
        "cancel", "actually", "no wait", "wait wait",
        "oops", "sorry"
    ]

    /// Only apply the shrinkage heuristic once the raw transcript has at least
    /// this many words; below it, filler removal can easily halve a short
    /// transcript and would cause false positives.
    static let shrinkageMinimumRawWords = 8

    /// Processed word count must stay at or above this fraction of the raw
    /// word count. Anything lower looks like the provider summarized the
    /// transcript. Tuned to ~50% per the observed over-transformation.
    static let shrinkageMinimumRatio = 0.5

    /// Returns a validation error when the processed output looks suspicious,
    /// otherwise `nil`. Checks aggressive shrinkage first, then rogue markdown.
    /// Kept conservative to avoid false positives on legitimate corrections and
    /// explicit formatting commands.
    static func suspiciousPostProcessingError(raw: String, processed: String) -> PostProcessingValidationError? {
        if let error = suspiciousShrinkageError(raw: raw, processed: processed) {
            return error
        }
        if let error = rogueMarkdownError(raw: raw, processed: processed) {
            return error
        }
        return nil
    }

    static func suspiciousShrinkageError(raw: String, processed: String) -> PostProcessingValidationError? {
        let rawWords = wordCount(raw)
        guard rawWords >= shrinkageMinimumRawWords else { return nil }
        // Explicit self-corrections legitimately shrink the output; don't
        // second-guess them.
        guard !containsCorrectionTrigger(raw) else { return nil }
        let processedWords = wordCount(processed)
        guard Double(processedWords) / Double(rawWords) >= shrinkageMinimumRatio else {
            return PostProcessingValidationError(
                kind: .suspiciousShrinkage,
                detail: "output has \(processedWords) words vs \(rawWords) in the raw transcript"
            )
        }
        return nil
    }

    static func rogueMarkdownError(raw: String, processed: String) -> PostProcessingValidationError? {
        guard beginsWithMarkdownStructure(processed) else { return nil }
        guard !containsFormattingCommand(raw) else { return nil }
        return PostProcessingValidationError(
            kind: .rogueMarkdown,
            detail: "output introduces markdown formatting that was not dictated"
        )
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func containsFormattingCommand(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        return words.contains(where: { formattingCommandWords.contains(String($0)) })
    }

    static func containsCorrectionTrigger(_ text: String) -> Bool {
        let lower = text.lowercased()
        for phrase in correctionTriggerPhrases {
            var searchStart = lower.startIndex
            while searchStart < lower.endIndex {
                guard let range = lower.range(of: phrase, range: searchStart ..< lower.endIndex) else { break }
                let leftOK = range.lowerBound == lower.startIndex
                    || !lower[lower.index(before: range.lowerBound)].isLetter
                let rightOK = range.upperBound == lower.endIndex
                    || !lower[range.upperBound].isLetter
                if leftOK && rightOK {
                    return true
                }
                searchStart = range.upperBound
            }
        }
        return false
    }

    /// True when the processed output opens with a markdown structural marker
    /// (ATX heading, bullet list, or ordered list) on its first non-empty line.
    static func beginsWithMarkdownStructure(_ processed: String) -> Bool {
        guard let firstLine = processed.split(separator: "\n", omittingEmptySubsequences: true).first else {
            return false
        }
        let trimmed = String(firstLine).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("#") { return true } // ATX heading
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true // bullet list
        }
        // Ordered list: one or more digits immediately followed by ".".
        var index = trimmed.startIndex
        var sawDigit = false
        while index < trimmed.endIndex, trimmed[index].isNumber {
            sawDigit = true
            index = trimmed.index(after: index)
        }
        if sawDigit, index < trimmed.endIndex, trimmed[index] == "." {
            return true
        }
        return false
    }
}
