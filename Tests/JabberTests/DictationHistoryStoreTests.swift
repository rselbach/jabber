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

    func testDecodesLegacyEntryMissingPostProcessingFields() throws {
        // Simulates a metadata.json written before post-processing existed:
        // no rawTranscript / wasPostProcessed / postProcessingErrorDescription keys.
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "timestamp": "2024-01-01T00:00:00Z",
            "duration": 0.5,
            "sampleRate": 16000,
            "modelID": "qwen3",
            "modelName": "Qwen3-ASR",
            "language": "en",
            "transcript": "cool cool cool",
            "directoryName": "legacy",
            "audioFilename": "audio.wav",
            "audioByteCount": 84
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let entry = try decoder.decode(DictationHistoryEntry.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(entry.transcript, "cool cool cool")
        XCTAssertNil(entry.rawTranscript)
        XCTAssertFalse(entry.wasPostProcessed)
        XCTAssertNil(entry.postProcessingErrorDescription)
    }

    func testSaveRoundTripsPostProcessingMetadata() async throws {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_735_689_600)

        let entry = try await store.save(DictationHistorySession(
            samples: [0, 0.5, -1, 1],
            transcript: "Hello.",
            modelID: AppMode.qwen3ModelId,
            language: "en",
            timestamp: timestamp,
            rawTranscript: " um hello ",
            wasPostProcessed: true,
            postProcessingErrorDescription: nil
        ))

        let entries = await store.entries()
        XCTAssertEqual(entries.count, 1)
        let loaded = try XCTUnwrap(entries.first)
        XCTAssertEqual(loaded.id, entry.id)
        XCTAssertEqual(loaded.transcript, "Hello.")
        XCTAssertEqual(loaded.rawTranscript, " um hello ")
        XCTAssertTrue(loaded.wasPostProcessed)
        XCTAssertNil(loaded.postProcessingErrorDescription)
    }

    func testSaveRoundTripsPostProcessingErrorDescription() async throws {
        let store = makeStore()

        _ = try await store.save(DictationHistorySession(
            samples: [0.25],
            transcript: "raw fallback",
            modelID: AppMode.qwen3ModelId,
            language: "en",
            rawTranscript: nil,
            wasPostProcessed: false,
            postProcessingErrorDescription: "boom"
        ))

        let entries = await store.entries()
        let loaded = try XCTUnwrap(entries.first)
        XCTAssertEqual(loaded.transcript, "raw fallback")
        XCTAssertFalse(loaded.wasPostProcessed)
        XCTAssertEqual(loaded.postProcessingErrorDescription, "boom")
    }

    // MARK: - Bug 1: save() must not leave orphan directories on failure

    func testSaveFailureLeavesNoOrphanDirectory() async throws {
        let store = makeStore()

        // Pre-create the history root with normal (writable) permissions so the
        // entry subdirectory can be created, then force newly-created
        // subdirectories to be non-writable (mode 0555) so the audio file write
        // inside the entry directory fails with EACCES. `umask` is process-wide,
        // so it applies to the actor's file operations too; it is restored the
        // instant the call returns. This reproduces the "failure after entry
        // directory creation" class of bugs that previously left orphans.
        try FileManager.default.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)

        let previousMask = umask(0o222)
        var thrown: Error?
        do {
            _ = try await store.save(session(
                transcript: "Troy and Abed in the morning",
                timestamp: Date(timeIntervalSince1970: 100)
            ))
        } catch {
            thrown = error
        }
        umask(previousMask)

        XCTAssertNotNil(thrown, "save should fail when the entry directory is non-writable")

        let remaining = try FileManager.default.contentsOfDirectory(
            at: historyDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertTrue(remaining.isEmpty, "a failed save must not leave an orphan entry directory behind")
    }

    // MARK: - Bug 2: retention must sweep orphans before applying limits

    func testRetentionPrunesOrphanEntryDirectories() async throws {
        let store = makeStore()

        // Plant an orphan: an entry directory with audio.wav but no metadata.json.
        let orphanDir = historyDirectoryURL
            .appendingPathComponent("2024-01-01T00-00-00Z-orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: orphanDir.appendingPathComponent("audio.wav"))

        // Saving a real session triggers enforceRetentionLimit, which should
        // sweep the orphan before applying count/byte limits.
        _ = try await store.save(session(
            transcript: "Troy and Abed in the morning",
            timestamp: Date(timeIntervalSince1970: 100)
        ))

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDir.path), "orphan entry directory should be pruned")
        let entries = await store.entries()
        XCTAssertEqual(entries.map(\.transcript), ["Troy and Abed in the morning"])
    }

    func testOrphanBytesDoNotEvictValidEntries() async throws {
        // Tight byte budget that the orphan alone exceeds, but a single valid
        // entry fits within. Before the fix the orphan's bytes counted against
        // the budget and evicted the only valid entry; the sweep must prevent
        // that starvation.
        let store = makeStore(maxByteCount: 4096)

        let orphanDir = historyDirectoryURL
            .appendingPathComponent("2024-01-01T00-00-00Z-orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 8192).write(to: orphanDir.appendingPathComponent("audio.wav"))

        _ = try await store.save(session(
            transcript: "Greendale Community College",
            timestamp: Date(timeIntervalSince1970: 100)
        ))

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDir.path), "orphan should be pruned first")
        let entries = await store.entries()
        XCTAssertEqual(entries.map(\.transcript), ["Greendale Community College"])
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
