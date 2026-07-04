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
}
