import AppKit
import Foundation
import MediaRemoteAdapter
import os

enum MediaRemoteCommand: Int32, Sendable {
    case play = 0
    case pause = 1

    var adapterArgument: String {
        switch self {
        case .play:
            return "play"
        case .pause:
            return "pause"
        }
    }
}

@MainActor
protocol MediaRemoteControlling: AnyObject {
    var isAvailable: Bool { get }
    func isPlaying() async -> Bool
    func send(_ command: MediaRemoteCommand) -> Bool
    func sendSystemPlayPauseKey() -> Bool
}

@MainActor
final class MediaPlaybackService: MediaPlaybackProtocol {
    static let shared = MediaPlaybackService()

    private let client: any MediaRemoteControlling
    private let isEnabled: @MainActor () -> Bool
    private let pauseVerificationDelay: Duration
    private var currentSessionID: UUID?
    private var didPauseMediaForThisSession = false
    private var pauseTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "MediaPlaybackService")

    init(
        client: any MediaRemoteControlling = MediaRemoteClient(),
        isEnabled: @escaping @MainActor () -> Bool = { TypedSettings[.pauseMediaDuringRecording] },
        pauseVerificationDelay: Duration = .milliseconds(150)
    ) {
        self.client = client
        self.isEnabled = isEnabled
        self.pauseVerificationDelay = pauseVerificationDelay
    }

    func pauseForDictationIfNeeded() {
        pauseTask?.cancel()
        pauseTask = nil
        currentSessionID = nil
        didPauseMediaForThisSession = false

        guard isEnabled() else {
            logger.notice("Media pause disabled; skipping media pause")
            return
        }
        guard client.isAvailable else {
            logger.notice("MediaRemote is unavailable; skipping media pause")
            return
        }

        let sessionID = UUID()
        currentSessionID = sessionID
        logger.notice("Checking media playback before dictation")
        pauseTask = Task { [weak self] in
            await self?.pauseCurrentMediaIfNeeded(sessionID: sessionID)
        }
    }

    func resumeAfterDictationIfNeeded() {
        pauseTask?.cancel()
        pauseTask = nil
        currentSessionID = nil

        let shouldResume = didPauseMediaForThisSession
        didPauseMediaForThisSession = false

        guard shouldResume else { return }
        logger.notice("Resuming media playback paused by Jabber")
        guard client.send(.play) else {
            logger.warning("MediaRemote failed to resume media playback")
            return
        }
    }

    private func pauseCurrentMediaIfNeeded(sessionID: UUID) async {
        let isPlaying = await client.isPlaying()
        logger.notice("MediaRemote reported isPlaying=\(isPlaying)")

        guard isPlaying else {
            logger.notice("No active media playback detected; skipping media pause")
            return
        }
        guard currentSessionID == sessionID, !Task.isCancelled else { return }

        guard client.send(.pause) else {
            logger.warning("MediaRemote failed to pause media playback")
            pauseWithSystemMediaKeyIfStillPlaying(sessionID: sessionID)
            return
        }

        logger.notice("Paused media playback for dictation")
        didPauseMediaForThisSession = true

        guard await waitBeforeVerifyingPause() else { return }
        guard currentSessionID == sessionID, !Task.isCancelled else { return }
        guard await client.isPlaying() else { return }

        logger.warning("MediaRemote pause command returned success, but media is still playing; sending system media key fallback")
        pauseWithSystemMediaKeyIfStillPlaying(sessionID: sessionID)
    }

    private func pauseWithSystemMediaKeyIfStillPlaying(sessionID: UUID) {
        guard currentSessionID == sessionID, !Task.isCancelled else { return }
        guard client.sendSystemPlayPauseKey() else {
            logger.warning("System media key fallback failed")
            return
        }

        didPauseMediaForThisSession = true
    }

    private func waitBeforeVerifyingPause() async -> Bool {
        do {
            try await Task.sleep(for: pauseVerificationDelay)
            return true
        } catch is CancellationError {
            return false
        } catch {
            logger.error("Failed while waiting to verify media pause: \(error.localizedDescription)")
            return false
        }
    }
}

@MainActor
final class MediaRemoteClient: MediaRemoteControlling {
    private static let queryTimeout: DispatchTimeInterval = .milliseconds(500)

    private let processQueue = DispatchQueue(label: "com.rselbach.jabber.mediaremote-adapter", qos: .userInitiated)
    private let libraryURL: URL?
    private let scriptURL: URL?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "MediaRemoteClient")

    var isAvailable: Bool {
        libraryURL != nil && scriptURL != nil
    }

    init() {
        let libraryURL = Bundle(for: MediaController.self).executableURL
        self.libraryURL = libraryURL
        scriptURL = Self.findScriptURL(libraryURL: libraryURL)

        if libraryURL == nil {
            logger.warning("Could not locate MediaRemoteAdapter dynamic library")
        }
        if scriptURL == nil {
            logger.warning("Could not locate MediaRemoteAdapter run.pl resource")
        }
    }

    func isPlaying() async -> Bool {
        guard let libraryURL, let scriptURL else { return false }

        let snapshot = await fetchTrackSnapshot(scriptURL: scriptURL, libraryURL: libraryURL)
        guard let snapshot else {
            logger.notice("MediaRemoteAdapter returned no track info")
            return false
        }

        logger.notice(
            "MediaRemoteAdapter track app=\(snapshot.applicationName, privacy: .public), bundle=\(snapshot.bundleIdentifier, privacy: .public), title=\(snapshot.title, privacy: .private), isPlaying=\(snapshot.isPlayingDescription, privacy: .public), playbackRate=\(snapshot.playbackRateDescription, privacy: .public), determinedPlaying=\(snapshot.isPlaying)"
        )

        return snapshot.isPlaying
    }

    func send(_ command: MediaRemoteCommand) -> Bool {
        guard let libraryURL, let scriptURL else { return false }

        let processQueue = processQueue
        let logger = logger
        processQueue.async {
            let result = Self.runAdapterCommand(
                scriptURL: scriptURL,
                libraryURL: libraryURL,
                arguments: [command.adapterArgument]
            )
            guard result.terminationStatus != 0 else { return }

            logger.warning(
                "MediaRemoteAdapter \(command.adapterArgument, privacy: .public) command failed with status \(result.terminationStatus): \(result.errorOutput, privacy: .public)"
            )
        }

        return true
    }

    func sendSystemPlayPauseKey() -> Bool {
        postSystemMediaKey(Int32(NX_KEYTYPE_PLAY))
    }

    private func fetchTrackSnapshot(scriptURL: URL, libraryURL: URL) async -> AdapterTrackSnapshot? {
        await withCheckedContinuation { continuation in
            let box = SingleResumeBox(continuation)
            let logger = logger
            processQueue.async {
                let snapshot = Self.loadTrackSnapshot(
                    scriptURL: scriptURL,
                    libraryURL: libraryURL,
                    logger: logger
                )
                box.resume(returning: snapshot)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.queryTimeout) { [logger] in
                if box.resume(returning: nil) {
                    logger.notice("Timed out while querying MediaRemoteAdapter track info")
                }
            }
        }
    }

    nonisolated private static func loadTrackSnapshot(
        scriptURL: URL,
        libraryURL: URL,
        logger: Logger
    ) -> AdapterTrackSnapshot? {
        let result = runAdapterCommand(scriptURL: scriptURL, libraryURL: libraryURL, arguments: ["get"])
        guard result.terminationStatus == 0 else {
            logger.warning(
                "MediaRemoteAdapter get command failed with status \(result.terminationStatus): \(result.errorOutput, privacy: .public)"
            )
            return nil
        }

        guard let line = result.outputLines.first else { return nil }
        guard line != "NIL" else { return nil }

        do {
            let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: Data(line.utf8))
            return AdapterTrackSnapshot(trackInfo: trackInfo)
        } catch {
            logger.warning("Failed to decode MediaRemoteAdapter track info: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated private static func runAdapterCommand(
        scriptURL: URL,
        libraryURL: URL,
        arguments: [String]
    ) -> AdapterCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, libraryURL.path] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return AdapterCommandResult(
                output: "",
                errorOutput: error.localizedDescription,
                terminationStatus: -1
            )
        }

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return AdapterCommandResult(
            output: output,
            errorOutput: errorOutput,
            terminationStatus: process.terminationStatus
        )
    }

    nonisolated private static func findScriptURL(libraryURL: URL?) -> URL? {
        let adapterBundleName = "MediaRemoteAdapter_MediaRemoteAdapter.bundle"
        let relativeScriptPath = "\(adapterBundleName)/run.pl"
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(relativeScriptPath))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(relativeScriptPath))

        if let libraryURL {
            let libraryDirectory = libraryURL.deletingLastPathComponent()
            candidates.append(libraryDirectory.appendingPathComponent(relativeScriptPath))
            candidates.append(
                libraryDirectory
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources")
                    .appendingPathComponent(relativeScriptPath)
            )
        }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func postSystemMediaKey(_ keyCode: Int32) -> Bool {
        postSystemMediaKey(keyCode, keyState: Int32(NX_KEYDOWN))
            && postSystemMediaKey(keyCode, keyState: Int32(NX_KEYUP))
    }

    private func postSystemMediaKey(_ keyCode: Int32, keyState: Int32) -> Bool {
        let data1 = Int((keyCode << 16) | (keyState << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }
}

private struct AdapterCommandResult: Sendable {
    let output: String
    let errorOutput: String
    let terminationStatus: Int32

    var outputLines: [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct AdapterTrackSnapshot: Sendable {
    let applicationName: String
    let bundleIdentifier: String
    let title: String
    let isPlayingDescription: String
    let playbackRateDescription: String
    let isPlaying: Bool

    init(trackInfo: TrackInfo) {
        let payload = trackInfo.payload
        applicationName = payload.applicationName ?? "Unknown"
        bundleIdentifier = payload.bundleIdentifier ?? "Unknown"
        title = payload.title ?? "Unknown"
        isPlayingDescription = payload.isPlaying.map { String($0) } ?? "nil"
        playbackRateDescription = payload.playbackRate.map { String($0) } ?? "nil"
        isPlaying = payload.isPlaying ?? ((payload.playbackRate ?? 0) > 0)
    }
}

private final class SingleResumeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: T) -> Bool {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else { return false }
        continuation.resume(returning: value)
        return true
    }
}
