import Foundation
import os

struct DictationHistorySession: Sendable {
    let samples: [Float]
    let transcript: String
    let modelID: String
    let language: String
    let timestamp: Date

    init(
        samples: [Float],
        transcript: String,
        modelID: String,
        language: String,
        timestamp: Date = Date()
    ) {
        self.samples = samples
        self.transcript = transcript
        self.modelID = modelID
        self.language = language
        self.timestamp = timestamp
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
    let audioFilename: String
    let audioByteCount: Int64
}

protocol DictationHistoryProtocol: AnyObject, Sendable {
    func saveSession(_ session: DictationHistorySession) async
}

actor DictationHistoryStore: DictationHistoryProtocol {
    static let shared = DictationHistoryStore()
    static let sampleRate = 16_000
    static let defaultMaxEntryCount = 50
    static let defaultMaxByteCount: Int64 = 500 * 1024 * 1024

    private static let metadataFilename = "metadata.json"
    private static let audioFilename = "audio.wav"

    private let directoryURL: URL
    private let maxEntryCount: Int
    private let maxByteCount: Int64
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "DictationHistoryStore")

    init(
        directoryURL: URL = DictationHistoryStore.defaultDirectoryURL,
        maxEntryCount: Int = DictationHistoryStore.defaultMaxEntryCount,
        maxByteCount: Int64 = DictationHistoryStore.defaultMaxByteCount,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.maxEntryCount = maxEntryCount
        self.maxByteCount = maxByteCount
        self.fileManager = fileManager
    }

    nonisolated static var defaultDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Jabber", isDirectory: true)
            .appendingPathComponent("DictationHistory", isDirectory: true)
    }

    func saveSession(_ session: DictationHistorySession) async {
        let isEnabled = await MainActor.run { TypedSettings[.saveHistoryEnabled] }
        guard isEnabled else { return }

        do {
            _ = try save(session)
        } catch {
            logger.error("Failed to save dictation history: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func save(_ session: DictationHistorySession) throws -> DictationHistoryEntry {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let entryID = UUID()
        let entryDirectoryName = Self.entryDirectoryName(timestamp: session.timestamp, id: entryID)
        let entryDirectoryURL = directoryURL.appendingPathComponent(entryDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: entryDirectoryURL, withIntermediateDirectories: true)

        let audioURL = entryDirectoryURL.appendingPathComponent(Self.audioFilename)
        let audioData = try Self.wavData(samples: session.samples, sampleRate: Self.sampleRate)
        try audioData.write(to: audioURL, options: .atomic)

        let entry = DictationHistoryEntry(
            id: entryID,
            timestamp: session.timestamp,
            duration: Double(session.samples.count) / Double(Self.sampleRate),
            sampleRate: Self.sampleRate,
            modelID: session.modelID,
            modelName: Self.modelName(for: session.modelID),
            language: session.language,
            transcript: session.transcript,
            directoryName: entryDirectoryName,
            audioFilename: Self.audioFilename,
            audioByteCount: Int64(audioData.count)
        )

        let metadataURL = entryDirectoryURL.appendingPathComponent(Self.metadataFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(entry)
        try metadataData.write(to: metadataURL, options: .atomic)

        try enforceRetentionLimit()
        return entry
    }

    func entries() -> [DictationHistoryEntry] {
        do {
            return try loadEntries()
        } catch {
            logger.error("Failed to load dictation history: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated func audioURL(for entry: DictationHistoryEntry) -> URL {
        directoryURL
            .appendingPathComponent(entry.directoryName, isDirectory: true)
            .appendingPathComponent(entry.audioFilename)
    }

    nonisolated func historyDirectoryURL() -> URL {
        directoryURL
    }

    private func loadEntries() throws -> [DictationHistoryEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        let entryDirectories = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var entries: [DictationHistoryEntry] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for entryDirectory in entryDirectories {
            let metadataURL = entryDirectory.appendingPathComponent(Self.metadataFilename)
            guard fileManager.fileExists(atPath: metadataURL.path) else { continue }

            do {
                let metadataData = try Data(contentsOf: metadataURL)
                try entries.append(decoder.decode(DictationHistoryEntry.self, from: metadataData))
            } catch {
                logger.error("Failed to read dictation history metadata at \(metadataURL.path): \(error.localizedDescription)")
            }
        }

        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    private func enforceRetentionLimit() throws {
        var entries = try loadEntries().sorted { $0.timestamp > $1.timestamp }
        var totalByteCount = try totalHistoryByteCount()

        while entries.count > maxEntryCount || totalByteCount > maxByteCount {
            guard let entryToRemove = entries.popLast() else { break }
            let entryURL = directoryURL.appendingPathComponent(entryToRemove.directoryName, isDirectory: true)
            let removedByteCount = try byteCount(at: entryURL)
            try fileManager.removeItem(at: entryURL)
            totalByteCount = max(0, totalByteCount - removedByteCount)
        }
    }

    private func totalHistoryByteCount() throws -> Int64 {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return 0 }
        return try byteCount(at: directoryURL)
    }

    private func byteCount(at url: URL) throws -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        }

        let files = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var total: Int64 = 0
        for fileURL in files {
            total += try byteCount(at: fileURL)
        }
        return total
    }

    private static func entryDirectoryName(timestamp: Date, id: UUID) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampString = formatter.string(from: timestamp)
            .replacingOccurrences(of: ":", with: "-")
        return "\(timestampString)-\(id.uuidString)"
    }

    private static func modelName(for modelID: String) -> String {
        AppMode.qwen3ASRVariant(for: modelID)?.name ?? modelID
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
