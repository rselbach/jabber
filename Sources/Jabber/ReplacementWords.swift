import Foundation
import os

/// A user-defined phrase-replacement rule. One entry can carry several
/// `triggers` (entered comma-separated in the UI) that all expand to the same
/// `replacement`. Persisted as JSON in UserDefaults via
/// `ReplacementEntriesCodec`.
struct ReplacementEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var triggers: [String]
    var replacement: String

    init(id: UUID = UUID(), triggers: [String], replacement: String) {
        self.id = id
        self.triggers = triggers
        self.replacement = replacement
    }
}

/// Encodes/decodes `[ReplacementEntry]` to/from the JSON string persisted in
/// UserDefaults. An empty array round-trips as an empty string. Decoding
/// errors (e.g. corrupted JSON from a manual `defaults write` edit) are logged
/// and recover as an empty list rather than crashing — the user can re-add
/// their rules. Errors are never swallowed silently: every failure path logs.
enum ReplacementEntriesCodec {
    private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "ReplacementEntries")

    static func encode(_ entries: [ReplacementEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(entries)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            logger.error("Failed to encode replacement entries: \(error.localizedDescription)")
            return ""
        }
    }

    static func decode(_ raw: String) -> [ReplacementEntry] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            logger.error("Replacement entries JSON was not valid UTF-8; ignoring")
            return []
        }
        do {
            return try JSONDecoder().decode([ReplacementEntry].self, from: data)
        } catch {
            logger.error("Failed to decode replacement entries, ignoring: \(error.localizedDescription)")
            return []
        }
    }
}

/// Pure helper that applies `ReplacementEntry` rules to a transcript and
/// returns the replaced text. Has no UserDefaults or UI dependencies, so it is
/// fully unit-testable in isolation.
///
/// Used by `DictationCoordinator` as a deterministic final pass applied AFTER
/// post-processing/refinement and BEFORE output, so what gets typed matches
/// what gets stored in history.
enum ReplacementWordsResolver {
    /// One normalized trigger paired with its literal replacement.
    private struct Rule {
        let trigger: String
        let replacement: String
    }

    /// Applies `entries` to `transcript` and returns the replaced text.
    ///
    /// Matching semantics:
    /// - Case-insensitive, literal phrases.
    /// - Whole-word-ish boundaries: the characters immediately before and
    ///   after a match (if any) must not be a letter or digit, so triggers can
    ///   sit next to punctuation ("Troy," / "(Troy)") without matching
    ///   substrings of larger words ("TroyBarnes").
    /// - Multi-word triggers are supported.
    /// - Replacement output is literal, exactly as typed.
    ///
    /// The transcript is scanned left-to-right in a single pass. At each
    /// position the longest matching trigger wins. Matched spans are emitted
    /// as the literal replacement and are NOT re-scanned, so replacements
    /// never chain into one another.
    static func resolve(transcript: String, entries: [ReplacementEntry]) -> String {
        let rules = buildRules(from: entries)
        guard !rules.isEmpty else { return transcript }

        var output = String()
        output.reserveCapacity(transcript.count)
        var scanIndex = transcript.startIndex
        let endIndex = transcript.endIndex

        while scanIndex < endIndex {
            if let matchEnd = longestMatch(in: transcript, at: scanIndex, rules: rules) {
                output += matchEnd.replacement
                scanIndex = matchEnd.rangeUpperBound
            } else {
                output.append(transcript[scanIndex])
                scanIndex = transcript.index(after: scanIndex)
            }
        }
        return output
    }

    /// Builds the normalized rule list from entries. Triggers are trimmed and
    /// lowercased; empty triggers and entries with an empty replacement are
    /// dropped. Duplicate triggers (case-insensitive) collapse to the first
    /// occurrence, preserving entry order so order/conflicts are predictable.
    private static func buildRules(from entries: [ReplacementEntry]) -> [Rule] {
        var rules: [Rule] = []
        var seen = Set<String>()
        for entry in entries {
            let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !replacement.isEmpty else { continue }
            for trigger in entry.triggers {
                let normalized = trigger.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                rules.append(Rule(trigger: normalized, replacement: replacement))
            }
        }
        return rules
    }

    /// Finds the longest rule whose trigger matches at `position` (case-
    /// insensitive, anchored) and sits on word boundaries. Returns the index
    /// just past the match together with the literal replacement, or `nil` if
    /// no rule matches at `position`.
    private static func longestMatch(
        in transcript: String,
        at position: String.Index,
        rules: [Rule]
    ) -> (rangeUpperBound: String.Index, replacement: String)? {
        var best: (rangeUpperBound: String.Index, replacement: String)?

        for rule in rules {
            guard let range = transcript.range(
                of: rule.trigger,
                options: [.caseInsensitive, .anchored],
                range: position ..< transcript.endIndex
            ) else { continue }
            guard isLeftBoundary(at: range.lowerBound, in: transcript),
                  isRightBoundary(at: range.upperBound, in: transcript) else { continue }
            // "Longest" is measured in the transcript, not the trigger: full
            // case folding can match spans of a different length than the
            // trigger ("strasse" matches "straße"). All matches anchor at
            // `position`, so the farthest upper bound is the longest match;
            // ties keep the earlier rule, preserving entry order.
            if best == nil || range.upperBound > best!.rangeUpperBound {
                best = (range.upperBound, rule.replacement)
            }
        }
        return best
    }

    /// True when the character before `index` (if any) is not a letter/digit.
    private static func isLeftBoundary(at index: String.Index, in string: String) -> Bool {
        guard index > string.startIndex else { return true }
        let char = string[string.index(before: index)]
        return !char.isLetter && !char.isNumber
    }

    /// True when the character at `index` (if any) is not a letter/digit.
    private static func isRightBoundary(at index: String.Index, in string: String) -> Bool {
        guard index < string.endIndex else { return true }
        let char = string[index]
        return !char.isLetter && !char.isNumber
    }
}
