import XCTest
@testable import Jabber

@MainActor
final class MediaPlaybackServiceTests: XCTestCase {
    func testLoadedAdapterLibraryURLResolvesLoadedDylib() {
        // The test process loads libMediaRemoteAdapter.dylib at launch (JabberTests → Jabber →
        // MediaRemoteAdapter dynamic library), so the resolver must find it on the dyld image list.
        let url = MediaRemoteClient.loadedAdapterLibraryURL()
        XCTAssertNotNil(url, "libMediaRemoteAdapter.dylib should be loaded in the test process")
        XCTAssertEqual(url?.lastPathComponent, "libMediaRemoteAdapter.dylib")
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "resolved dylib path should exist on disk")
        }
    }

    private var client: FakeMediaRemoteClient!

    override func setUp() async throws {
        try await super.setUp()
        client = FakeMediaRemoteClient()
    }

    override func tearDown() async throws {
        client = nil
        try await super.tearDown()
    }

    func testDisabledSettingDoesNotPauseOrResume() async throws {
        let service = makeService(isEnabled: false)

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()

        XCTAssertEqual(client.isPlayingCallCount, 0)
        XCTAssertTrue(client.commands.isEmpty)
    }

    func testDoesNotResumeWhenMediaWasNotPlaying() async throws {
        client.isPlayingResult = false
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()

        XCTAssertEqual(client.isPlayingCallCount, 1)
        XCTAssertTrue(client.commands.isEmpty)
    }

    func testResumesOnlyAfterSuccessfulPause() async throws {
        client.isPlayingResults = [true, false]
        let playSent = expectation(description: "resume sends play")
        client.sendExpectations[.play] = playSent
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()
        await fulfillment(of: [playSent], timeout: 1.0)

        XCTAssertEqual(client.commands, [.pause, .play])
        XCTAssertEqual(client.systemPlayPauseCallCount, 0)
    }

    func testDoesNotResumeWhenPauseCommandFails() async throws {
        client.isPlayingResult = true
        client.commandResults[.pause] = false
        client.systemPlayPauseResult = false
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()

        XCTAssertEqual(client.commands, [.pause])
    }

    func testFallsBackToSystemMediaKeyWhenPauseCommandDoesNotStopPlayback() async throws {
        client.isPlayingResults = [true, true]
        let playSent = expectation(description: "resume sends play")
        client.sendExpectations[.play] = playSent
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()
        await fulfillment(of: [playSent], timeout: 1.0)

        XCTAssertEqual(client.commands, [.pause, .play])
        XCTAssertEqual(client.systemPlayPauseCallCount, 1)
    }

    /// A failed play command must still clear the should-resume flag, so a
    /// later resume call can't replay it. This exercises the failure branch of
    /// `send(.play)` that was unreachable when `send` always returned `true`.
    func testResumeDoesNotReplayAfterFailedPlay() async throws {
        client.isPlayingResults = [true, false]
        client.commandResults[.play] = false
        let playSent = expectation(description: "resume attempts play once")
        client.sendExpectations[.play] = playSent
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()
        await fulfillment(of: [playSent], timeout: 1.0)

        // Second resume must not send play again: the flag was cleared even
        // though the play command failed. No async work is spawned here, so the
        // command log is stable.
        service.resumeAfterDictationIfNeeded()
        XCTAssertEqual(client.commands, [.pause, .play])
    }

    func testFinishingBeforePlaybackQueryReturnsPreventsLatePause() async throws {
        client.holdIsPlayingUntilReleased = true
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()
        client.releaseIsPlaying(true)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(client.commands.isEmpty)
    }

    func testFinishingDuringPauseCommandUnpausesStaleSession() async {
        client.isPlayingResult = true
        client.holdSendUntilReleased = true
        let pauseStarted = expectation(description: "pause send starts")
        client.sendExpectations[.pause] = pauseStarted
        let playSent = expectation(description: "stale pause is undone with play")
        client.sendExpectations[.play] = playSent
        let service = makeService()

        service.pauseForDictationIfNeeded()
        await fulfillment(of: [pauseStarted], timeout: 1.0)

        service.resumeAfterDictationIfNeeded()
        client.releaseSend(true)
        await fulfillment(of: [playSent], timeout: 1.0)

        XCTAssertEqual(client.commands, [.pause, .play])
    }

    // MARK: - Stale resume race (fast double-tap of the hotkey)

    /// Session A ends and session B starts before session A's resume Task runs.
    /// The resume must abort — sending .play would un-pause media session B
    /// intends to keep paused.
    func testStaleResumeAbortsWhenNewSessionStartedBeforePlayLands() async throws {
        // Session A: media playing, pause succeeds, verification sees paused.
        client.isPlayingResults = [true, false]
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))

        // Session A ends, then session B starts immediately. The resume Task
        // from session A is enqueued but hasn't run yet (main actor is busy
        // with the synchronous pause call). When it runs, currentSessionID is
        // session B's — the resume must abort instead of sending .play.
        service.resumeAfterDictationIfNeeded()
        service.pauseForDictationIfNeeded()

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(
            client.commands.contains(.play),
            "stale resume must not send .play when a new session started; commands: \(client.commands)"
        )
    }

    /// Same race as above, one step further: the aborted resume must hand the
    /// pause ownership to session B. B's probe saw media already paused and
    /// skipped, so without the handoff B's resume never sends .play and the
    /// user's media stays paused forever.
    func testAbortedStaleResumeHandsPauseOwnershipToNewSession() async throws {
        // Session A: media playing, pause succeeds, verification sees paused.
        // Session B's probe then sees paused media and skips its own pause.
        client.isPlayingResults = [true, false, false]
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))

        // A ends and B starts before A's resume Task runs; the resume aborts.
        service.resumeAfterDictationIfNeeded()
        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(client.commands.contains(.play))

        // B ends: it inherited the pause from A, so its resume must send .play.
        let playSent = expectation(description: "session B resume sends play")
        client.sendExpectations[.play] = playSent
        service.resumeAfterDictationIfNeeded()
        await fulfillment(of: [playSent], timeout: 1.0)

        XCTAssertEqual(client.commands, [.pause, .play])
    }

    /// Session A's .pause is in flight when A ends and session B starts. The
    /// landed pause is exactly what B wants: the stale task must NOT undo it
    /// with .play (that would un-pause media mid-dictation of B with nothing
    /// left to re-pause it) and must hand B the pause ownership instead.
    func testPauseLandingAfterNewSessionStartsTransfersOwnershipInsteadOfUnpausing() async throws {
        // A's probe sees playing; B's probe sees paused (A's pause landed
        // just before it) and skips.
        client.isPlayingResults = [true, false]
        client.holdSendUntilReleased = true
        let pauseStarted = expectation(description: "session A pause send starts")
        client.sendExpectations[.pause] = pauseStarted
        let service = makeService()

        service.pauseForDictationIfNeeded()
        await fulfillment(of: [pauseStarted], timeout: 1.0)

        // A ends, B starts while A's .pause is still in flight.
        service.resumeAfterDictationIfNeeded()
        service.pauseForDictationIfNeeded()

        // A's .pause lands with session B active: no .play undo.
        client.releaseSend(true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(
            client.commands.contains(.play),
            "stale pause must not be undone while a new session is active; commands: \(client.commands)"
        )

        // B ends: it inherited the pause, so its resume must send .play.
        let playSent = expectation(description: "session B resume sends play")
        client.sendExpectations[.play] = playSent
        service.resumeAfterDictationIfNeeded()
        await fulfillment(of: [playSent], timeout: 1.0)

        XCTAssertEqual(client.commands, [.pause, .play])
    }

    /// Session A's resume .play is in flight when session B starts. The resume
    /// must re-pause after the .play lands so media stays paused for session B.
    func testStaleResumeRepausesWhenNewSessionStartsDuringPlay() async throws {
        // Session A: media playing, pause succeeds, verification sees paused.
        client.isPlayingResults = [true, false]
        client.holdSendUntilReleased = true
        let pauseSent = expectation(description: "session A pause send starts")
        client.sendExpectations[.pause] = pauseSent
        let service = makeService()

        service.pauseForDictationIfNeeded()
        await fulfillment(of: [pauseSent], timeout: 1.0)
        // Clear the pause expectation so the later re-pause doesn't double-fulfill.
        client.sendExpectations[.pause] = nil
        client.releaseSend(true)
        try await Task.sleep(for: .milliseconds(20))

        // Session A ends: resume sends .play. Hold it so we can race a new
        // session into the middle of the await.
        client.holdSendUntilReleased = true
        let playStarted = expectation(description: "resume .play send starts (held)")
        client.sendExpectations[.play] = playStarted
        service.resumeAfterDictationIfNeeded()
        await fulfillment(of: [playStarted], timeout: 1.0)

        // New session B starts while session A's resume .play is in flight.
        // isPlayingResults is exhausted, so session B's pauseTask sees
        // isPlaying=false and does not send .pause — the only .pause after
        // the .play should be the resume Task's safety re-pause.
        service.pauseForDictationIfNeeded()

        // Release the .play. The resume Task must detect the new session and
        // re-pause so media stays paused for session B.
        client.releaseSend(true)
        try await Task.sleep(for: .milliseconds(50))

        let commands = client.commands
        XCTAssertTrue(commands.contains(.play), "resume must have sent .play; commands: \(commands)")
        let lastPauseIndex = commands.lastIndex(of: .pause)
        let playIndex = commands.firstIndex(of: .play)
        if let lastPauseIndex, let playIndex {
            XCTAssertTrue(
                lastPauseIndex > playIndex,
                "a .pause must follow the .play (stale resume re-pause); commands: \(commands)"
            )
        } else {
            XCTFail("expected [.pause, .play, .pause] but got \(commands)")
        }
    }

    // MARK: - runProcess pipe drain + timeout (deadlock regression)

    /// 100_000 bytes far exceeds the ~64KB pipe buffer. With read-after-
    /// waitUntilExit the child blocks on write, the parent blocks in
    /// waitUntilExit, and the serial processQueue hangs forever. Concurrent
    /// drain must complete and return the full payload.
    func testRunProcessDrainsLargeOutputWithoutDeadlock() {
        let result = MediaRemoteClient.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "print q{A} x 100000"],
            timeout: .seconds(5)
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.output.count, 100_000)
        XCTAssertTrue(result.errorOutput.isEmpty)
    }

    /// A stuck child is SIGTERM'd at the timeout so the queue can't hang
    /// forever. The failure is surfaced (status -1 + a timeout message), not
    /// swallowed.
    func testRunProcessTerminatesStuckChildOnTimeout() {
        let start = Date()
        let result = MediaRemoteClient.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "sleep 30"],
            timeout: .milliseconds(200)
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.terminationStatus, -1)
        XCTAssertTrue(result.errorOutput.contains("timed out"))
        // Returns promptly (not after the full 30s sleep), with slack for scheduling.
        XCTAssertLessThan(elapsed, 5.0)
    }

    func testRunProcessKillsChildThatIgnoresTermination() {
        let start = Date()
        let result = MediaRemoteClient.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "local $SIG{TERM} = sub {}; sleep 30"],
            timeout: .milliseconds(200)
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.terminationStatus, -1)
        XCTAssertTrue(result.errorOutput.contains("timed out"))
        XCTAssertLessThan(elapsed, 5.0)
    }

    private func makeService(isEnabled: Bool = true) -> MediaPlaybackService {
        MediaPlaybackService(
            client: client,
            isEnabled: { isEnabled },
            pauseVerificationDelay: .milliseconds(1)
        )
    }
}

@MainActor
final class FakeMediaRemoteClient: MediaRemoteControlling {
    var isAvailable = true
    var isPlayingResult = false
    var isPlayingResults: [Bool] = []
    var holdIsPlayingUntilReleased = false
    var holdSendUntilReleased = false
    var commandResults: [MediaRemoteCommand: Bool] = [:]
    var systemPlayPauseResult = true
    /// Optional per-command expectation fulfilled when `send` is invoked, so
    /// callers can wait deterministically for a fire-and-forget resume Task
    /// instead of sleeping.
    var sendExpectations: [MediaRemoteCommand: XCTestExpectation] = [:]

    private(set) var isPlayingCallCount = 0
    private(set) var commands: [MediaRemoteCommand] = []
    private(set) var systemPlayPauseCallCount = 0
    private var isPlayingContinuation: CheckedContinuation<Bool, Never>?
    private var sendContinuation: CheckedContinuation<Bool, Never>?

    func isPlaying() async -> Bool {
        isPlayingCallCount += 1

        if holdIsPlayingUntilReleased {
            return await withCheckedContinuation { continuation in
                isPlayingContinuation = continuation
            }
        }

        if !isPlayingResults.isEmpty {
            return isPlayingResults.removeFirst()
        }

        return isPlayingResult
    }

    func send(_ command: MediaRemoteCommand) async -> Bool {
        commands.append(command)
        sendExpectations[command]?.fulfill()

        if holdSendUntilReleased {
            return await withCheckedContinuation { continuation in
                sendContinuation = continuation
            }
        }

        return commandResults[command] ?? true
    }

    func sendSystemPlayPauseKey() -> Bool {
        systemPlayPauseCallCount += 1
        return systemPlayPauseResult
    }

    func releaseIsPlaying(_ result: Bool) {
        let continuation = isPlayingContinuation
        isPlayingContinuation = nil
        continuation?.resume(returning: result)
    }

    func releaseSend(_ result: Bool) {
        holdSendUntilReleased = false
        let continuation = sendContinuation
        sendContinuation = nil
        continuation?.resume(returning: result)
    }
}
