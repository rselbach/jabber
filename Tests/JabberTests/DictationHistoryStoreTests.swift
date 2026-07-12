import XCTest
@testable import Jabber

final class DictationHistoryStoreTests: XCTestCase {
    private var historyDirectoryURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        historyDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JabberTests.DictationHistoryStore.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
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

    func testSaveEncodesNonFiniteSamplesWithoutTrapping() async throws {
        let store = makeStore()

        // NaN falls through both clamp ranges; Int16(NaN.rounded()) traps, so
        // one bad float from the capture pipeline crashed the history save.
        let entry = try await store.save(DictationHistorySession(
            samples: [Float.nan, .infinity, -.infinity, 0.5],
            transcript: "streets ahead",
            modelID: AppMode.qwen3ModelId,
            language: "en"
        ))

        let audioData = try Data(contentsOf: store.audioURL(for: entry))
        XCTAssertEqual(audioData.count, 44 + 4 * 2)
        // NaN encodes as silence; infinities clamp to the extremes.
        let pcmBytes = [UInt8](audioData.suffix(8))
        func pcmSample(_ index: Int) -> Int16 {
            Int16(bitPattern: UInt16(pcmBytes[2 * index]) | (UInt16(pcmBytes[2 * index + 1]) << 8))
        }
        XCTAssertEqual(pcmSample(0), 0)
        XCTAssertEqual(pcmSample(1), Int16.max)
        XCTAssertEqual(pcmSample(2), Int16.min)
    }

    func testSaveSessionRequiresOptInSetting() async {
        let disabledStore = makeStore(isSaveEnabled: { false })

        await disabledStore.saveSession(session(transcript: "disabled", timestamp: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDirectoryURL.path))

        let enabledStore = makeStore(isSaveEnabled: { true })
        await enabledStore.saveSession(session(transcript: "enabled", timestamp: Date(timeIntervalSince1970: 200)))

        let entries = await enabledStore.entries()

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

    func testRetentionRemovesOldestValidEntriesByByteCount() async throws {
        let store = makeStore(maxByteCount: 5_000)

        let oldEntry = try await store.save(session(
            samples: Array(repeating: 0.25, count: 10_000),
            transcript: "Troy Barnes",
            timestamp: Date(timeIntervalSince1970: 100)
        ))
        _ = try await store.save(session(
            samples: Array(repeating: 0.25, count: 100),
            transcript: "Abed Nadir",
            timestamp: Date(timeIntervalSince1970: 200)
        ))
        _ = try await store.save(session(
            samples: Array(repeating: 0.25, count: 100),
            transcript: "Annie Edison",
            timestamp: Date(timeIntervalSince1970: 300)
        ))

        let entries = await store.entries()

        XCTAssertEqual(entries.map(\.transcript), ["Annie Edison", "Abed Nadir"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: historyDirectoryURL.appendingPathComponent(oldEntry.directoryName).path
        ))
    }

    func testSaveKeepsReturnedEntryWhenSingleSessionExceedsByteCount() async throws {
        let store = makeStore(maxByteCount: 1)

        let entry = try await store.save(session(
            samples: Array(repeating: 0.25, count: 100),
            transcript: "Greendale Human Being",
            timestamp: Date(timeIntervalSince1970: 100)
        ))

        let entries = await store.entries()

        XCTAssertEqual(entries.map(\.id), [entry.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioURL(for: entry).path))
    }

    func testOversizedSessionCanBeEvictedByNextSave() async throws {
        let store = makeStore(maxByteCount: 1_200)

        let oversizedEntry = try await store.save(session(
            samples: Array(repeating: 0.25, count: 10_000),
            transcript: "Pierce Hawthorne",
            timestamp: Date(timeIntervalSince1970: 100)
        ))
        let smallEntry = try await store.save(session(
            samples: Array(repeating: 0.25, count: 10),
            transcript: "Shirley Bennett",
            timestamp: Date(timeIntervalSince1970: 200)
        ))

        let entries = await store.entries()

        XCTAssertEqual(entries.map(\.id), [smallEntry.id])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: historyDirectoryURL.appendingPathComponent(oversizedEntry.directoryName).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioURL(for: smallEntry).path))
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

    // MARK: - Bug 3: corrupt metadata.json must be pruned, not just missing

    func testSaveRecordsHumanReadableModelNameForNonQwenModels() async throws {
        // The history entry's `modelName` label must show the human-readable
        // display name for every model family, not just Qwen3. Previously the
        // qwen3ASRVariant lookup returned nil for nemotron/apple-speech and the
        // raw id leaked into the UI.
        let store = makeStore()
        let tests: [String: (modelID: String, want: String)] = [
            "nemotron": (AppMode.nemotronModelId, "Nemotron"),
            "apple-speech": (AppMode.appleSpeechModelId, "Apple Speech"),
            "qwen3": (AppMode.qwen3ModelId, "Qwen3-ASR 1.7B 8-bit")
        ]

        for (name, tc) in tests {
            let entry = try await store.save(DictationHistorySession(
                samples: [0.25],
                transcript: "Greendale Community College",
                modelID: tc.modelID,
                language: "en",
                timestamp: Date(timeIntervalSince1970: 100)
            ))
            XCTAssertEqual(entry.modelName, tc.want, name)
        }
    }

    func testRetentionPrunesCorruptMetadataEntryDirectories() async throws {
        let store = makeStore()

        // Plant a corrupt entry: valid audio.wav but metadata.json is garbage
        // JSON. loadEntries() skips it (decode fails) but totalHistoryByteCount
        // still counts its audio, so without pruning it survives forever.
        let corruptDir = historyDirectoryURL
            .appendingPathComponent("2024-01-01T00-00-00Z-corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: corruptDir.appendingPathComponent("audio.wav"))
        try Data("{ not valid json".utf8).write(to: corruptDir.appendingPathComponent("metadata.json"))

        // Saving a real session triggers enforceRetentionLimit, which should
        // sweep the corrupt entry before applying count/byte limits.
        _ = try await store.save(session(
            transcript: "Troy and Abed in the morning",
            timestamp: Date(timeIntervalSince1970: 100)
        ))

        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptDir.path), "corrupt entry directory should be pruned")
        let entries = await store.entries()
        XCTAssertEqual(entries.map(\.transcript), ["Troy and Abed in the morning"])
    }

    func testCorruptMetadataBytesDoNotEvictValidEntries() async throws {
        // Tight byte budget that the corrupt entry alone exceeds, but a single
        // valid entry fits within. Before the fix the corrupt entry's bytes
        // counted against the budget (loadEntries skipped it but
        // totalHistoryByteCount did not), evicting the only valid entry.
        let store = makeStore(maxByteCount: 4096)

        let corruptDir = historyDirectoryURL
            .appendingPathComponent("2024-01-01T00-00-00Z-corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 8192).write(to: corruptDir.appendingPathComponent("audio.wav"))
        try Data("{ not valid json".utf8).write(to: corruptDir.appendingPathComponent("metadata.json"))

        _ = try await store.save(session(
            transcript: "Señor Chang's Spanish class",
            timestamp: Date(timeIntervalSince1970: 100)
        ))

        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptDir.path), "corrupt entry should be pruned first")
        let entries = await store.entries()
        XCTAssertEqual(entries.map(\.transcript), ["Señor Chang's Spanish class"])
    }

    // MARK: - Bug 4: path traversal via tampered metadata.json directoryName

    func testLoadEntriesRejectsPathTraversalDirectoryName() async throws {
        let store = makeStore()

        // Plant a malicious entry whose metadata.json advertises ".." as its
        // directoryName. URL.appendingPathComponent does NOT strip "..", so
        // without validation audioURL(for:) would resolve to the parent of the
        // history directory.
        let maliciousDir = historyDirectoryURL
            .appendingPathComponent("2024-01-01T00-00-00Z-malicious", isDirectory: true)
        try FileManager.default.createDirectory(at: maliciousDir, withIntermediateDirectories: true)
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: maliciousDir.appendingPathComponent("audio.wav"))
        let maliciousJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "timestamp": "2024-01-01T00:00:00Z",
            "duration": 0.5,
            "sampleRate": 16000,
            "modelID": "qwen3",
            "modelName": "Qwen3-ASR",
            "language": "en",
            "transcript": "malicious",
            "directoryName": "..",
            "audioFilename": "audio.wav",
            "audioByteCount": 84
        }
        """
        try Data(maliciousJSON.utf8).write(to: maliciousDir.appendingPathComponent("metadata.json"))

        // Saving a real session triggers enforceRetentionLimit, which reuses
        // decodeEntry and should sweep the rejected (unsafe-name) entry before
        // applying count/byte limits.
        _ = try await store.save(session(
            transcript: "Troy and Abed in the morning",
            timestamp: Date(timeIntervalSince1970: 100)
        ))

        let entries = await store.entries()
        XCTAssertEqual(entries.map(\.transcript), ["Troy and Abed in the morning"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: maliciousDir.path), "malicious entry directory should be pruned")
    }

    func testAudioURLSanitizesUnsafeDirectoryName() {
        let store = makeStore()

        // Defense-in-depth: even if a caller hand-constructs an entry with a
        // traversal-style directoryName, audioURL(for:) must stay inside the
        // history directory. Without sanitization, ".." would resolve via
        // standardizedFileURL to a sibling of the history dir, not a child.
        let malicious = DictationHistoryEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            duration: 0.5,
            sampleRate: 16_000,
            modelID: AppMode.qwen3ModelId,
            modelName: "Qwen3-ASR",
            language: "en",
            transcript: "Señor Chang",
            directoryName: "..",
            audioFilename: "audio.wav",
            audioByteCount: 84
        )

        let audioURL = store.audioURL(for: malicious)
        let historyPath = historyDirectoryURL.standardizedFileURL.path
        let resolvedPath = audioURL.standardizedFileURL.path

        XCTAssertTrue(
            resolvedPath.hasPrefix(historyPath),
            "audioURL must stay inside history directory; got \(resolvedPath) (history root: \(historyPath))"
        )
        XCTAssertTrue(
            audioURL.path.contains("__invalid_entry__"),
            "audioURL should use the safety sentinel for unsafe directoryName; got \(audioURL.path)"
        )
    }

    private func makeStore(
        maxEntryCount: Int = 50,
        maxByteCount: Int64 = 500 * 1024 * 1024,
        isSaveEnabled: @escaping @MainActor () -> Bool = { true }
    ) -> DictationHistoryStore {
        DictationHistoryStore(
            directoryURL: historyDirectoryURL,
            maxEntryCount: maxEntryCount,
            maxByteCount: maxByteCount,
            isSaveEnabled: isSaveEnabled
        )
    }

    private func session(
        samples: [Float] = Array(repeating: 0.25, count: 100),
        transcript: String,
        timestamp: Date
    ) -> DictationHistorySession {
        DictationHistorySession(
            samples: samples,
            transcript: transcript,
            modelID: AppMode.qwen3ModelId,
            language: "auto",
            timestamp: timestamp
        )
    }
}
