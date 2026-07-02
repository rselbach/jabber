import XCTest
@testable import Jabber

final class DictationHistoryStoreTests: XCTestCase {
    private var historyDirectoryURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: AppSettingKey.saveHistoryEnabled)
        historyDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JabberTests.DictationHistoryStore.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: AppSettingKey.saveHistoryEnabled)
        if let historyDirectoryURL, FileManager.default.fileExists(atPath: historyDirectoryURL.path) {
            try FileManager.default.removeItem(at: historyDirectoryURL)
        }
        historyDirectoryURL = nil
        try await super.tearDown()
    }

    func testSaveWritesWAVAndMetadata() async throws {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_735_689_600)

        let entry = try await store.save(DictationHistorySession(
            samples: [0, 0.5, -1, 1],
            transcript: "cool cool cool",
            modelID: AppMode.qwen3ModelId,
            language: "en",
            timestamp: timestamp
        ))

        let audioURL = store.audioURL(for: entry)
        let audioData = try Data(contentsOf: audioURL)
        XCTAssertEqual(String(data: Data(audioData.prefix(4)), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: Data(audioData[8 ..< 12]), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: Data(audioData[36 ..< 40]), encoding: .ascii), "data")
        XCTAssertEqual(audioData.count, 44 + 4 * 2)

        let metadataURL = historyDirectoryURL
            .appendingPathComponent(entry.directoryName, isDirectory: true)
            .appendingPathComponent("metadata.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedEntry = try decoder.decode(
            DictationHistoryEntry.self,
            from: Data(contentsOf: metadataURL)
        )

        XCTAssertEqual(decodedEntry.id, entry.id)
        XCTAssertEqual(decodedEntry.transcript, "cool cool cool")
        XCTAssertEqual(decodedEntry.modelID, AppMode.qwen3ModelId)
        XCTAssertEqual(decodedEntry.modelName, "Qwen3-ASR 1.7B 8-bit")
        XCTAssertEqual(decodedEntry.language, "en")
        XCTAssertEqual(decodedEntry.duration, 4.0 / 16_000.0, accuracy: 0.000_001)
    }

    func testSaveSessionRequiresOptInSetting() async {
        let store = makeStore()

        await store.saveSession(session(transcript: "disabled", timestamp: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDirectoryURL.path))

        UserDefaults.standard.set(true, forKey: AppSettingKey.saveHistoryEnabled)
        await store.saveSession(session(transcript: "enabled", timestamp: Date(timeIntervalSince1970: 200)))

        let entries = await store.entries()

        XCTAssertEqual(entries.map(\.transcript), ["enabled"])
    }

    func testEntriesAreSortedNewestFirst() async throws {
        let store = makeStore()

        _ = try await store.save(session(transcript: "first", timestamp: Date(timeIntervalSince1970: 100)))
        _ = try await store.save(session(transcript: "second", timestamp: Date(timeIntervalSince1970: 200)))
        _ = try await store.save(session(transcript: "third", timestamp: Date(timeIntervalSince1970: 150)))

        let entries = await store.entries()

        XCTAssertEqual(entries.map(\.transcript), ["second", "third", "first"])
    }

    func testRetentionRemovesOldestEntriesByCount() async throws {
        let store = makeStore(maxEntryCount: 2)

        let oldEntry = try await store.save(session(transcript: "old", timestamp: Date(timeIntervalSince1970: 100)))
        _ = try await store.save(session(transcript: "middle", timestamp: Date(timeIntervalSince1970: 200)))
        _ = try await store.save(session(transcript: "new", timestamp: Date(timeIntervalSince1970: 300)))

        let entries = await store.entries()

        XCTAssertEqual(entries.map(\.transcript), ["new", "middle"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: historyDirectoryURL.appendingPathComponent(oldEntry.directoryName).path
        ))
    }

    private func makeStore(maxEntryCount: Int = 50, maxByteCount: Int64 = 500 * 1024 * 1024) -> DictationHistoryStore {
        DictationHistoryStore(
            directoryURL: historyDirectoryURL,
            maxEntryCount: maxEntryCount,
            maxByteCount: maxByteCount
        )
    }

    private func session(transcript: String, timestamp: Date) -> DictationHistorySession {
        DictationHistorySession(
            samples: Array(repeating: 0.25, count: 100),
            transcript: transcript,
            modelID: AppMode.qwen3ModelId,
            language: "auto",
            timestamp: timestamp
        )
    }
}
