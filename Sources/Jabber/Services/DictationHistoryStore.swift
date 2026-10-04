import Foundation
import os

struct DictationHistorySession: Sendable {
    let samples: [Float]
    let transcript: String
    let modelID: String
    let language: String
    let timestamp: Date
    /// Raw ASR transcript before post-processing. Only set when the session
    /// was actually post-processed; otherwise `nil` and `transcript` is the
    /// raw text. Additive — old sessions stay valid.
    let rawTranscript: String?
    let wasPostProcessed: Bool
    let postProcessingErrorDescription: String?
    /// The app the transcript went into, when known.
    let app: DictatedApp?

    init(
        samples: [Float],
        transcript: String,
        modelID: String,
        language: String,
        timestamp: Date = Date(),
        rawTranscript: String? = nil,
        wasPostProcessed: Bool = false,
        postProcessingErrorDescription: String? = nil,
        app: DictatedApp? = nil
    ) {
        self.samples = samples
        self.transcript = transcript
        self.modelID = modelID
        self.language = language
        self.timestamp = timestamp
        self.rawTranscript = rawTranscript
        self.wasPostProcessed = wasPostProcessed
        self.postProcessingErrorDescription = postProcessingErrorDescription
        self.app = app
    }
}

struct DictationHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    let sampleRate: Int
    let modelID: String
    let modelName: String
    let language: String
    let transcript: String
    let directoryName: String
    /// `nil` when the audio was not kept, or was dropped to stay within the
    /// audio budget.
    let audioFilename: String?
    let audioByteCount: Int64
    /// Additive fields for Apple Intelligence post-processing metadata.
    /// Optional/defaulting so entries written before this feature existed
    /// still decode cleanly.
    let rawTranscript: String?
    let wasPostProcessed: Bool
    let postProcessingErrorDescription: String?
    /// The app the transcript went into, when known. Additive.
    let appName: String?
    let appBundleID: String?

    init(
        id: UUID,
        timestamp: Date,
        duration: TimeInterval,
        sampleRate: Int,
        modelID: String,
        modelName: String,
        language: String,
        transcript: String,
        directoryName: String,
        audioFilename: String?,
        audioByteCount: Int64,
        rawTranscript: String? = nil,
        wasPostProcessed: Bool = false,
        postProcessingErrorDescription: String? = nil,
        appName: String? = nil,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.sampleRate = sampleRate
        self.modelID = modelID
        self.modelName = modelName
        self.language = language
        self.transcript = transcript
        self.directoryName = directoryName
        self.audioFilename = audioFilename
        self.audioByteCount = audioByteCount
        self.rawTranscript = rawTranscript
        self.wasPostProcessed = wasPostProcessed
        self.postProcessingErrorDescription = postProcessingErrorDescription
        self.appName = appName
        self.appBundleID = appBundleID
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, duration, sampleRate, modelID, modelName, language
        case transcript, directoryName, audioFilename, audioByteCount
        case rawTranscript, wasPostProcessed, postProcessingErrorDescription
        case appName, appBundleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        modelID = try container.decode(String.self, forKey: .modelID)
        modelName = try container.decode(String.self, forKey: .modelName)
        language = try container.decode(String.self, forKey: .language)
        transcript = try container.decode(String.self, forKey: .transcript)
        directoryName = try container.decode(String.self, forKey: .directoryName)
        // Additive fields: missing keys (old entries) fall back to defaults.
        audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
        audioByteCount = try container.decodeIfPresent(Int64.self, forKey: .audioByteCount) ?? 0
        rawTranscript = try container.decodeIfPresent(String.self, forKey: .rawTranscript)
        wasPostProcessed = try container.decodeIfPresent(Bool.self, forKey: .wasPostProcessed) ?? false
        postProcessingErrorDescription = try container.decodeIfPresent(String.self, forKey: .postProcessingErrorDescription)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
    }

    var hasAudio: Bool {
        audioFilename != nil
    }

    /// This entry once its audio file is gone.
    func withoutAudio() -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: id,
            timestamp: timestamp,
            duration: duration,
            sampleRate: sampleRate,
            modelID: modelID,
            modelName: modelName,
            language: language,
            transcript: transcript,
            directoryName: directoryName,
            audioFilename: nil,
            audioByteCount: 0,
            rawTranscript: rawTranscript,
            wasPostProcessed: wasPostProcessed,
            postProcessingErrorDescription: postProcessingErrorDescription,
            appName: appName,
            appBundleID: appBundleID
        )
    }
}

protocol DictationHistoryProtocol: AnyObject, Sendable {
    func saveSession(_ session: DictationHistorySession) async
}

/// Saved dictations, one directory per entry holding `metadata.json` and,
/// when audio is kept, `audio.wav`. Transcripts expire with the retention
/// setting; audio has its own, smaller budget, and dropping audio keeps the
/// transcript.
actor DictationHistoryStore: DictationHistoryProtocol {
    static let shared = DictationHistoryStore()
    static let sampleRate = 16_000
    static let defaultMaxEntryCount = 1_000
    static let defaultMaxAudioEntryCount = 50
    static let defaultMaxAudioByteCount: Int64 = 500 * 1024 * 1024

    private static let metadataFilename = "metadata.json"
    private static let audioFilename = "audio.wav"

    private let directoryURL: URL
    private let maxEntryCount: Int
    private let maxAudioEntryCount: Int
    private let maxAudioByteCount: Int64
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let preferences: @MainActor @Sendable () -> DictationHistoryPreferences
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "DictationHistoryStore")
    /// Entries newest first. Loaded from disk on first use, then kept in step
    /// with every change, so saving never rescans the directory.
    private var cachedEntries: [DictationHistoryEntry]?
    private var isDirectoryPrepared = false

    init(
        directoryURL: URL = DictationHistoryStore.defaultDirectoryURL,
        maxEntryCount: Int = DictationHistoryStore.defaultMaxEntryCount,
        maxAudioEntryCount: Int = DictationHistoryStore.defaultMaxAudioEntryCount,
        maxAudioByteCount: Int64 = DictationHistoryStore.defaultMaxAudioByteCount,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        preferences: @escaping @MainActor @Sendable () -> DictationHistoryPreferences = { TypedSettings.historyPreferences }
    ) {
        self.directoryURL = directoryURL
        self.maxEntryCount = maxEntryCount
        self.maxAudioEntryCount = maxAudioEntryCount
        self.maxAudioByteCount = maxAudioByteCount
        self.fileManager = fileManager
        self.now = now
        self.preferences = preferences
    }

    nonisolated static var defaultDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Jabber", isDirectory: true)
            .appendingPathComponent("DictationHistory", isDirectory: true)
    }

    func saveSession(_ session: DictationHistorySession) async {
        let preferences = await MainActor.run { self.preferences() }
        guard preferences.isEnabled else { return }

        do {
            _ = try save(session, keepingAudio: preferences.keepsAudio, retention: preferences.retention)
        } catch {
            logger.error("Failed to save dictation history: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func save(
        _ session: DictationHistorySession,
        keepingAudio: Bool,
        retention: HistoryRetention
    ) throws -> DictationHistoryEntry {
        var entries = try loadedEntries()
        try prepareDirectory()

        let entryID = UUID()
        let entryDirectoryName = Self.entryDirectoryName(timestamp: session.timestamp, id: entryID)
        let entryDirectoryURL = directoryURL.appendingPathComponent(entryDirectoryName, isDirectory: true)

        let entry: DictationHistoryEntry
        do {
            try fileManager.createDirectory(at: entryDirectoryURL, withIntermediateDirectories: true)

            var audioFilename: String?
            var audioByteCount: Int64 = 0
            if keepingAudio {
                let audioData = try Self.wavData(samples: session.samples, sampleRate: Self.sampleRate)
                try audioData.write(to: entryDirectoryURL.appendingPathComponent(Self.audioFilename), options: .atomic)
                audioFilename = Self.audioFilename
                audioByteCount = Int64(audioData.count)
            }

            entry = DictationHistoryEntry(
                id: entryID,
                timestamp: session.timestamp,
                duration: Double(session.samples.count) / Double(Self.sampleRate),
                sampleRate: Self.sampleRate,
                modelID: session.modelID,
                modelName: Self.modelName(for: session.modelID),
                language: session.language,
                transcript: session.transcript,
                directoryName: entryDirectoryName,
                audioFilename: audioFilename,
                audioByteCount: audioByteCount,
                rawTranscript: session.rawTranscript,
                wasPostProcessed: session.wasPostProcessed,
                postProcessingErrorDescription: session.postProcessingErrorDescription,
                appName: session.app?.name,
                appBundleID: session.app?.bundleID
            )
            try writeMetadata(entry, in: entryDirectoryURL)
        } catch {
            // A failure after the entry directory is created (e.g. the audio or
            // metadata write failing on ENOSPC) would otherwise leave an
            // orphaned directory that loadEntries() skips. Remove it, then
            // rethrow.
            do {
                try fileManager.removeItem(at: entryDirectoryURL)
            } catch {
                logger.error("Failed to clean up partial dictation history entry at \(entryDirectoryURL.path): \(error.localizedDescription)")
            }
            throw error
        }

        let insertionIndex = entries.firstIndex { $0.timestamp < entry.timestamp } ?? entries.endIndex
        entries.insert(entry, at: insertionIndex)
        cachedEntries = entries
        try enforceRetention(retention, protecting: entry.id)
        notifyChange()
        return entry
    }

    /// Entries newest first.
    func entries() -> [DictationHistoryEntry] {
        do {
            return try loadedEntries()
        } catch {
            logger.error("Failed to load dictation history: \(error.localizedDescription)")
            return []
        }
    }

    /// Removes what `retention` no longer covers, such as after the setting
    /// was shortened or the app sat idle past an entry's expiry.
    func applyRetention(_ retention: HistoryRetention) throws {
        if try enforceRetention(retention, protecting: nil) {
            notifyChange()
        }
    }

    func delete(id: UUID) throws {
        var entries = try loadedEntries()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        try removeEntryDirectory(entries[index])
        entries.remove(at: index)
        cachedEntries = entries
        notifyChange()
    }

    func deleteAll() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
        cachedEntries = []
        isDirectoryPrepared = false
        notifyChange()
    }

    /// The entry's recording, or `nil` when no audio was kept.
    nonisolated func audioURL(for entry: DictationHistoryEntry) -> URL? {
        guard let audioFilename = entry.audioFilename else { return nil }
        // Defense-in-depth against path traversal via a tampered metadata.json:
        // primary validation is in decodeEntry (which rejects unsafe names so
        // they never reach callers), but audioURL must never escape the
        // history directory even if a caller hand-constructs an entry.
        return entryDirectoryURL(for: entry)
            .appendingPathComponent(Self.sanitizedPathComponent(audioFilename))
    }

    nonisolated func historyDirectoryURL() -> URL {
        directoryURL
    }

    private nonisolated func entryDirectoryURL(for entry: DictationHistoryEntry) -> URL {
        directoryURL.appendingPathComponent(Self.sanitizedPathComponent(entry.directoryName), isDirectory: true)
    }

    private nonisolated func notifyChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: Constants.Notifications.dictationHistoryDidChange, object: nil)
        }
    }

    private func loadedEntries() throws -> [DictationHistoryEntry] {
        if let cachedEntries {
            return cachedEntries
        }
        try pruneOrphanEntryDirectories()
        let entries = try loadEntries()
        cachedEntries = entries
        return entries
    }

    /// Creates the history directory and keeps it out of backups: it holds
    /// what the user said, and expiring it here should mean it is gone.
    private func prepareDirectory() throws {
        guard !isDirectoryPrepared else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directoryURL
        do {
            try url.setResourceValues(values)
        } catch {
            logger.error("Failed to exclude dictation history from backups: \(error.localizedDescription)")
        }
        isDirectoryPrepared = true
    }

    private func writeMetadata(_ entry: DictationHistoryEntry, in entryDirectoryURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(
            to: entryDirectoryURL.appendingPathComponent(Self.metadataFilename),
            options: .atomic
        )
    }

    private func removeEntryDirectory(_ entry: DictationHistoryEntry) throws {
        let url = entryDirectoryURL(for: entry)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func loadEntries() throws -> [DictationHistoryEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        let entryDirectories = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var entries: [DictationHistoryEntry] = []

        for entryDirectory in entryDirectories {
            let metadataURL = entryDirectory.appendingPathComponent(Self.metadataFilename)
            guard fileManager.fileExists(atPath: metadataURL.path) else { continue }
            if let entry = decodeEntry(at: metadataURL) {
                entries.append(entry)
            }
        }

        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    /// Decodes a single entry's `metadata.json`, logging (not swallowing) the
    /// failure. Shared by `loadEntries` (which skips corrupt entries) and
    /// `pruneOrphanEntryDirectories` (which removes them) so the two passes
    /// agree on what "corrupt" means.
    private func decodeEntry(at metadataURL: URL) -> DictationHistoryEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let metadataData = try Data(contentsOf: metadataURL)
            let entry = try decoder.decode(DictationHistoryEntry.self, from: metadataData)
            // Reject entries whose persisted names could escape the history
            // directory (path traversal via a tampered metadata.json).
            // pruneOrphanEntryDirectories reuses this decode path and removes
            // the rejected entry's directory when history first loads.
            guard Self.isSafePathComponent(entry.directoryName),
                  entry.audioFilename.map(Self.isSafePathComponent) ?? true else {
                logger.error("Rejecting dictation history entry at \(metadataURL.path): unsafe directoryName '\(entry.directoryName)' or audioFilename")
                return nil
            }
            return entry
        } catch {
            logger.error("Failed to read dictation history metadata at \(metadataURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes entries past the retention age or the entry cap, then the
    /// audio of the oldest recordings once the audio budget is spent. The
    /// entry being saved is never touched, so a single oversized recording
    /// stays until the next save. Returns whether anything changed.
    @discardableResult
    private func enforceRetention(_ retention: HistoryRetention, protecting protectedID: UUID?) throws -> Bool {
        let entries = try loadedEntries()
        let cutoff = retention.maxAge.map { now().addingTimeInterval(-$0) }
        var kept: [DictationHistoryEntry] = []
        var changed = false

        for entry in entries {
            let isExpired = cutoff.map { entry.timestamp < $0 } ?? false
            let isOverCap = kept.count >= maxEntryCount
            if entry.id != protectedID, isExpired || isOverCap {
                try removeEntryDirectory(entry)
                changed = true
            } else {
                kept.append(entry)
            }
        }

        var audioEntryCount = 0
        var audioByteCount: Int64 = 0
        var isAudioBudgetSpent = false
        for index in kept.indices where kept[index].hasAudio {
            let entry = kept[index]
            if entry.id != protectedID {
                isAudioBudgetSpent = isAudioBudgetSpent
                    || audioEntryCount >= maxAudioEntryCount
                    || audioByteCount + entry.audioByteCount > maxAudioByteCount
                if isAudioBudgetSpent {
                    kept[index] = try removingAudio(from: entry)
                    changed = true
                    continue
                }
            }
            audioEntryCount += 1
            audioByteCount += entry.audioByteCount
        }

        cachedEntries = kept
        return changed
    }

    /// Deletes the entry's audio first, so a failed metadata write can leave
    /// an entry pointing at missing audio but never audio that outlives its
    /// budget.
    private func removingAudio(from entry: DictationHistoryEntry) throws -> DictationHistoryEntry {
        if let audioURL = audioURL(for: entry), fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }
        let updated = entry.withoutAudio()
        try writeMetadata(updated, in: entryDirectoryURL(for: entry))
        return updated
    }

    /// Removes entry directories that `loadEntries()` cannot read, so they
    /// do not linger on disk unseen. Runs when history first loads. Two cases:
    /// - `metadata.json` missing (a partial write left an orphan).
    /// - `metadata.json` present but fails to decode or names an unsafe
    ///   path. Reuses the same decode path as loadEntries so the two passes
    ///   agree.
    private func pruneOrphanEntryDirectories() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }

        let entryDirectories = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for entryDirectory in entryDirectories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: entryDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let metadataURL = entryDirectory.appendingPathComponent(Self.metadataFilename)
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                try fileManager.removeItem(at: entryDirectory)
                continue
            }
            if decodeEntry(at: metadataURL) == nil {
                try fileManager.removeItem(at: entryDirectory)
            }
        }
    }

    private static func entryDirectoryName(timestamp: Date, id: UUID) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampString = formatter.string(from: timestamp)
            .replacingOccurrences(of: ":", with: "-")
        return "\(timestampString)-\(id.uuidString)"
    }

    /// A safe name contains no path separators and is not a path-traversal
    /// segment. Legitimate entry directory names produced by
    /// `entryDirectoryName(timestamp:id:)` (ISO8601 timestamp + UUID) and
    /// `audio.wav` are single path components and always satisfy this check.
    private static func isSafePathComponent(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
    }

    /// Returns `name` if it is safe, otherwise a sentinel that is a valid
    /// single path component but guaranteed not to match any real file, so
    /// callers' file-existence checks fail gracefully without escaping the
    /// history directory.
    private static func sanitizedPathComponent(_ name: String) -> String {
        isSafePathComponent(name) ? name : "__invalid_entry__"
    }

    private static func modelName(for modelID: String) -> String {
        // `modelDefinition` covers every model family and prevents history
        // entries from being labeled with raw model ids.
        AppMode.modelDefinition(for: modelID)?.name ?? modelID
    }

    private static func wavData(samples: [Float], sampleRate: Int) throws -> Data {
        let bytesPerSample = 2
        let channelCount = 1
        let bitsPerSample = 16
        let dataByteCount = samples.count * bytesPerSample
        guard dataByteCount <= Int(UInt32.max) - 36 else {
            throw DictationHistoryError.audioTooLarge
        }

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + dataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channelCount))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * channelCount * bytesPerSample))
        data.appendLittleEndian(UInt16(channelCount * bytesPerSample))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(dataByteCount))

        for sample in samples {
            data.appendLittleEndian(Self.pcm16Sample(from: sample))
        }

        return data
    }

    private static func pcm16Sample(from sample: Float) -> Int16 {
        // NaN matches neither range case (infinities clamp below) and would
        // fall through to the Int16 conversion, which traps — one bad float
        // from the capture pipeline must not crash a best-effort history save.
        guard !sample.isNaN else { return 0 }
        switch sample {
        case ...(-1):
            return Int16.min
        case 1...:
            return Int16.max
        default:
            return Int16((sample * Float(Int16.max)).rounded())
        }
    }
}

enum DictationHistoryError: Error, LocalizedError {
    case audioTooLarge

    var errorDescription: String? {
        switch self {
        case .audioTooLarge:
            return "Audio recording is too large to save as WAV"
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
