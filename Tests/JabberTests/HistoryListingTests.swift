import XCTest
@testable import Jabber

final class HistoryListingTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    func testFilterMatchesEveryWordAcrossTextAndApp() {
        let entries = [
            entry("Troy and Abed in the morning", app: "Greendale Messenger"),
            entry("Señor Chang's Spanish class", raw: "senor changs spanish class um"),
            entry("Six seasons and a movie")
        ]
        let tests: [String: (query: String, want: [String])] = [
            "empty query keeps everything": ("  ", entries.map(\.transcript)),
            "case and accents are ignored": ("senor CHANG", ["Señor Chang's Spanish class"]),
            "original transcript counts": ("um", ["Señor Chang's Spanish class"]),
            "app name counts": ("messenger morning", ["Troy and Abed in the morning"]),
            "every word must match": ("movie morning", [])
        ]

        for (name, tc) in tests {
            XCTAssertEqual(HistoryListing.filter(entries, query: tc.query).map(\.transcript), tc.want, name)
        }
    }

    func testSectionsGroupByDayNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_759_150_800) // Monday, September 29, 2025, 13:00 UTC
        let entries = [
            entry("this afternoon", at: now.addingTimeInterval(-60)),
            entry("this morning", at: now.addingTimeInterval(-12 * 60 * 60)),
            entry("last night", at: now.addingTimeInterval(-day)),
            entry("last week", at: now.addingTimeInterval(-7 * day)),
            entry("last year", at: now.addingTimeInterval(-365 * day))
        ]

        let sections = HistoryListing.sections(entries, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Monday, September 22", "September 29, 2024"])
        XCTAssertEqual(sections.map { $0.entries.map(\.transcript) }, [
            ["this afternoon", "this morning"],
            ["last night"],
            ["last week"],
            ["last year"]
        ])
    }

    func testExpiringCount() {
        let now = Date(timeIntervalSince1970: 100 * day)
        let entries = [
            entry("yesterday", at: now.addingTimeInterval(-day)),
            entry("last week", at: now.addingTimeInterval(-10 * day)),
            entry("last season", at: now.addingTimeInterval(-40 * day))
        ]
        let tests: [String: (retention: HistoryRetention, want: Int)] = [
            "one week": (.week, 2),
            "one month": (.month, 1),
            "forever": (.forever, 0)
        ]

        for (name, tc) in tests {
            XCTAssertEqual(HistoryListing.expiringCount(entries, retention: tc.retention, now: now), tc.want, name)
        }
    }

    func testOriginalTranscriptOnlyWhenCleanupChangedIt() {
        let tests: [String: (entry: DictationHistoryEntry, want: String?)] = [
            "cleaned up": (entry("Buy water.", raw: " um buy milk no wait buy water ", postProcessed: true), "um buy milk no wait buy water"),
            "cleanup changed nothing": (entry("Buy water.", raw: "Buy water.", postProcessed: true), nil),
            "not post-processed": (entry("buy water", raw: nil, postProcessed: false), nil),
            "empty original": (entry("Buy water.", raw: "  ", postProcessed: true), nil)
        ]

        for (name, tc) in tests {
            XCTAssertEqual(HistoryListing.originalTranscript(of: tc.entry), tc.want, name)
        }
    }

    private func entry(
        _ transcript: String,
        at timestamp: Date = Date(timeIntervalSince1970: 0),
        raw: String? = nil,
        postProcessed: Bool = true,
        app: String? = nil
    ) -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: UUID(),
            timestamp: timestamp,
            duration: 1,
            sampleRate: 16_000,
            modelID: AppMode.parakeetModelId,
            modelName: "Parakeet TDT v2",
            language: "en",
            transcript: transcript,
            directoryName: "entry",
            audioFilename: nil,
            audioByteCount: 0,
            rawTranscript: raw,
            wasPostProcessed: postProcessed,
            appName: app
        )
    }
}
