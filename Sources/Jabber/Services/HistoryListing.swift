import Foundation

/// How the History page searches, groups, and expires entries. Pure so the
/// rules are testable without the UI.
enum HistoryListing {
    struct DaySection: Identifiable, Equatable {
        /// Start of the day.
        let day: Date
        let title: String
        let entries: [DictationHistoryEntry]

        var id: Date {
            day
        }
    }

    /// Entries whose transcript, original transcript, or app name contain
    /// every word of `query`, ignoring case and accents.
    static func filter(_ entries: [DictationHistoryEntry], query: String) -> [DictationHistoryEntry] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let text = [entry.transcript, entry.rawTranscript, entry.appName]
                .compactMap { $0 }
                .joined(separator: " ")
            return words.allSatisfy { word in
                text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// Groups newest-first entries by day: Today, Yesterday, then the date.
    static func sections(
        _ entries: [DictationHistoryEntry],
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DaySection] {
        var sections: [DaySection] = []
        var currentDay: Date?
        var currentEntries: [DictationHistoryEntry] = []

        func closeSection() {
            guard let currentDay, !currentEntries.isEmpty else { return }
            sections.append(DaySection(
                day: currentDay,
                title: title(for: currentDay, now: now, calendar: calendar, locale: locale),
                entries: currentEntries
            ))
        }

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            if day != currentDay {
                closeSection()
                currentDay = day
                currentEntries = []
            }
            currentEntries.append(entry)
        }
        closeSection()
        return sections
    }

    static func title(for day: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = calendar.isDate(day, equalTo: now, toGranularity: .year)
            ? Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
            : Date.FormatStyle.dateTime.month(.wide).day().year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return day.formatted(style)
    }

    /// How many entries `retention` would remove right now.
    static func expiringCount(
        _ entries: [DictationHistoryEntry],
        retention: HistoryRetention,
        now: Date
    ) -> Int {
        guard let maxAge = retention.maxAge else { return 0 }
        let cutoff = now.addingTimeInterval(-maxAge)
        return entries.count { $0.timestamp < cutoff }
    }

    /// The transcript before post-processing, when cleanup changed it.
    static func originalTranscript(of entry: DictationHistoryEntry) -> String? {
        guard entry.wasPostProcessed,
              let raw = entry.rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != entry.transcript.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return raw
    }
}
