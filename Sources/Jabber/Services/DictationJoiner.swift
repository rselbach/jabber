import Foundation

/// Fits a dictation to the text just before the insertion point, so dictating
/// in bursts reads "Done. Next thing" instead of "Done.Next thing". Pure so
/// the rules are testable without a focused text field.
enum DictationJoiner {
    /// How much text before the insertion point the rules look at.
    static let lookbehindLength = 64

    /// Words a speech model capitalizes at the start of every utterance that
    /// usually continue a sentence instead.
    private static let continuationWords: Set<String> = [
        "a", "an", "and", "as", "because", "but", "for", "if", "nor", "or",
        "so", "the", "then", "though", "to", "when", "while", "yet"
    ]

    /// Returns `text` with a leading space when it would otherwise touch the
    /// preceding word, its first letter capitalized after a sentence end, and
    /// a capitalized continuation word ("And", "The") lowered mid-sentence.
    /// An empty `preceding` is the start of the field and leaves `text` as is.
    static func join(_ text: String, after preceding: String) -> String {
        guard let last = preceding.last, !text.isEmpty else { return text }

        var joined = setInitialCase(of: text, uppercase: isSentenceStart(preceding))
        let needsSpace = !last.isWhitespace
            && !"([{“‘".contains(last)
            && joined.first.map { !$0.isWhitespace && !",.?!;:)]}”’".contains($0) } == true
        if needsSpace {
            joined.insert(" ", at: joined.startIndex)
        }
        return joined
    }

    private static func isSentenceStart(_ preceding: String) -> Bool {
        let trimmed = preceding.reversed().drop { $0 == " " || $0 == "\t" }
        guard let last = trimmed.first else { return true }
        if last.isNewline {
            return true
        }
        let beforeClosers = trimmed.drop { "'\")]}”’".contains($0) }
        return beforeClosers.first.map { ".?!".contains($0) } == true
    }

    private static func setInitialCase(of text: String, uppercase: Bool) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        let character = text[index]
        let replacement: String
        if uppercase, character.isLowercase {
            replacement = character.uppercased()
        } else if !uppercase, character.isUppercase, startsWithContinuationWord(text[index...]) {
            replacement = character.lowercased()
        } else {
            return text
        }
        return text[..<index] + replacement + text[text.index(after: index)...]
    }

    private static func startsWithContinuationWord(_ text: Substring) -> Bool {
        let word = text.prefix { $0.isLetter || $0 == "'" }
        return continuationWords.contains(word.lowercased())
    }
}
