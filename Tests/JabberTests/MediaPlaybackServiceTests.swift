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
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()

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
        let service = makeService()

        service.pauseForDictationIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        service.resumeAfterDictationIfNeeded()

        XCTAssertEqual(client.commands, [.pause, .play])
        XCTAssertEqual(client.systemPlayPauseCallCount, 1)
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

    func send(_ command: MediaRemoteCommand) -> Bool {
        commands.append(command)
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
