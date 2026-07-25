import Foundation

/// Freezes the leading words that two consecutive preview decodes agree on so
/// text already on screen stops rewriting itself.
///
/// Every preview pass re-transcribes the whole utterance from scratch, and the
/// model routinely revises its last word or two once the next chunk of audio
/// arrives. Replacing the overlay text wholesale on each pass makes settled
/// words flicker; once two passes agree on a prefix, that prefix is committed
/// and only the unsettled tail keeps moving.
///
/// Preview only. The transcript that gets typed comes from a separate final
/// decode, so a word frozen here can never reach the output.
struct StreamingPreviewStabilizer {
    private var committedWords: [String] = []
    private var previousWords: [String] = []

    /// Returns the text to display for the newly decoded `text`.
    mutating func stabilize(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        defer { previousWords = words }

        // Commit the older spelling: both decodes agree apart from case and
        // punctuation, and the older one is already on screen, so freezing it
        // costs the reader nothing.
        let agreedCount = Self.agreementLength(previousWords, words)
        if agreedCount > committedWords.count {
            committedWords = Array(previousWords[0 ..< agreedCount])
        }

        guard words.count > committedWords.count else {
            return committedWords.joined(separator: " ")
        }
        return (committedWords + words[committedWords.count...]).joined(separator: " ")
    }

    mutating func reset() {
        committedWords.removeAll()
        previousWords.removeAll()
    }

    /// Number of leading words two decodes agree on, ignoring case and
    /// surrounding punctuation so "abed" and "Abed," count as the same word.
    private static func agreementLength(_ lhs: [String], _ rhs: [String]) -> Int {
        var count = 0
        for (left, right) in zip(lhs, rhs) {
            guard normalized(left) == normalized(right) else { break }
            count += 1
        }
        return count
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
