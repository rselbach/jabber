import XCTest
@testable import Jabber

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    private var audioCapture: FakeAudioCapture!
    private var transcriptionService: FakeTranscriptionService!
    private var typingService: FakeTypingService!
    private var mediaPlaybackService: FakeMediaPlaybackService!
    private var dictationHistoryStore: FakeDictationHistoryStore!
    private var coordinator: DictationCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        audioCapture = FakeAudioCapture()
        transcriptionService = FakeTranscriptionService()
        typingService = FakeTypingService()
        mediaPlaybackService = FakeMediaPlaybackService()
        dictationHistoryStore = FakeDictationHistoryStore()
        coordinator = DictationCoordinator(
            audioCapture: audioCapture,
            transcriptionService: transcriptionService,
            typingService: typingService,
            mediaPlaybackService: mediaPlaybackService,
            dictationHistoryStore: dictationHistoryStore,
            streamingPreviewInterval: .milliseconds(10),
            minimumStreamingPreviewSampleCount: 16_000
        )
    }

    override func tearDown() async throws {
        coordinator = nil
        audioCapture = nil
        transcriptionService = nil
        typingService = nil
        mediaPlaybackService = nil
        dictationHistoryStore = nil
        try await super.tearDown()
    }

    func testInitialStateIsIdle() {
        XCTAssertTrue(coordinator.isIdle)
        XCTAssertTrue(coordinator.canStart)
        XCTAssertFalse(coordinator.isRecording)
        XCTAssertFalse(coordinator.isTranscribing)
    }

    func testCanStartReflectsActivityState() {
        XCTAssertTrue(coordinator.canStart)

        XCTAssertTrue(coordinator.start())
        XCTAssertFalse(coordinator.canStart)

        coordinator.cancel()
        XCTAssertTrue(coordinator.canStart)
    }

    func testStartBeginsRecording() {
        XCTAssertTrue(coordinator.start())
        XCTAssertTrue(coordinator.isRecording)
        XCTAssertFalse(coordinator.isIdle)
        XCTAssertTrue(audioCapture.didStart)
    }

    func testStartRequestsMediaPause() {
        XCTAssertTrue(coordinator.start())

        XCTAssertEqual(mediaPlaybackService.pauseCallCount, 1)
        XCTAssertEqual(mediaPlaybackService.resumeCallCount, 0)
    }

    func testStartFailsWhenAlreadyRecording() {
        XCTAssertTrue(coordinator.start())
        XCTAssertFalse(coordinator.start())
    }

    func testStartFailsWhenTranscribing() {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("hello")
        transcriptionService.transcribeDelay = .milliseconds(50)

        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        XCTAssertTrue(coordinator.isTranscribing)

        XCTAssertFalse(coordinator.start())
    }

    func testStartFailsWhenAudioCaptureThrows() {
        audioCapture.startShouldSucceed = false

        var reportedError: Error?
        coordinator.onTranscriptionError = { error in
            reportedError = error
        }

        XCTAssertFalse(coordinator.start())
        XCTAssertTrue(coordinator.isIdle)
        XCTAssertNotNil(reportedError)
        XCTAssertEqual(mediaPlaybackService.pauseCallCount, 1)
        XCTAssertEqual(mediaPlaybackService.resumeCallCount, 1)
    }

    func testStopWithoutSpeechReturnsToIdle() {
        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        XCTAssertTrue(coordinator.isIdle)
        XCTAssertTrue(audioCapture.didStop)
        XCTAssertTrue(typingService.outputs.isEmpty)
        XCTAssertEqual(mediaPlaybackService.resumeCallCount, 1)
    }

    func testStopWithSpeechTranscribesAndOutputs() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("hello world")

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        XCTAssertTrue(coordinator.isTranscribing)
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertTrue(coordinator.isIdle)
        XCTAssertEqual(typingService.outputs, ["hello world"])
        XCTAssertEqual(typingService.targetProcessIDs, [nil])
    }

    func testStopWithSpeechSavesDictationHistoryAfterTranscriptionCompletes() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.currentModelID = AppMode.mediumModelId
        transcriptionService.transcribeResult = .success(" troy and abed in the morning ")

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(dictationHistoryStore.sessions.count, 1)
        XCTAssertEqual(dictationHistoryStore.sessions[0].samples, audioCapture.storedSamples)
        XCTAssertEqual(dictationHistoryStore.sessions[0].transcript, " troy and abed in the morning ")
        XCTAssertEqual(dictationHistoryStore.sessions[0].modelID, AppMode.mediumModelId)
        XCTAssertEqual(dictationHistoryStore.sessions[0].language, Constants.defaultLanguage)
    }

    func testStopWithSpeechResumesMediaAfterTranscriptionCompletes() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeDelay = .milliseconds(50)
        transcriptionService.transcribeResult = .success("six seasons and a movie")

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        XCTAssertTrue(coordinator.isTranscribing)
        XCTAssertEqual(mediaPlaybackService.resumeCallCount, 0)

        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(mediaPlaybackService.resumeCallCount, 1)
    }

    func testStopWithSpeechOutputsToCapturedTargetProcessID() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("cool cool cool")

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start(targetProcessID: 12_345))
        coordinator.stop()

        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(typingService.outputs, ["cool cool cool"])
        XCTAssertEqual(typingService.targetProcessIDs, [12_345])
    }

    func testStreamingPreviewPublishesPartialTextWhileRecording() async throws {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.streamingResult = .success("troy and abed")

        let partialExpectation = XCTestExpectation(description: "partial transcription published")
        var partialTranscriptions: [String] = []
        coordinator.onPartialTranscription = { text in
            partialTranscriptions.append(text)
            partialExpectation.fulfill()
        }

        XCTAssertTrue(coordinator.start())

        await fulfillment(of: [partialExpectation], timeout: 1.0)

        XCTAssertEqual(partialTranscriptions, ["troy and abed"])
        XCTAssertEqual(transcriptionService.streamingSampleCounts, [16_000])

        coordinator.cancel()
        try await Task.sleep(for: .milliseconds(20))
    }

    func testStreamingPreviewWaitsForInFlightChunkBeforeFinalTranscription() async throws {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.streamingResult = .success("preview")
        transcriptionService.holdStreamingUntilReleased = true
        transcriptionService.transcribeResult = .success("final")

        let partialStartedExpectation = XCTestExpectation(description: "streaming preview started")
        transcriptionService.onStreamingStarted = {
            partialStartedExpectation.fulfill()
        }

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start())
        await fulfillment(of: [partialStartedExpectation], timeout: 1.0)

        coordinator.stop()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(transcriptionService.callOrder, [.streaming])

        transcriptionService.releaseStreaming()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(transcriptionService.callOrder, [.streaming, .streamingFinished, .final])
        XCTAssertEqual(typingService.outputs, ["final"])
    }

    func testStreamingPreviewCanBeDisabledByTranscriptionService() async throws {
        transcriptionService.supportsStreamingTranscription = false
        audioCapture.storedSamples = makeLoudSamples()

        XCTAssertTrue(coordinator.start())
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(transcriptionService.streamingSampleCounts.isEmpty)
        coordinator.cancel()
    }

    func testStopWithEmptyTranscriptionShowsNoSpeechWarning() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("   ")

        var didShowNoSpeech = false
        coordinator.onNoSpeechDetected = {
            didShowNoSpeech = true
        }

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        await fulfillment(of: [idleExpectation], timeout: 1.0)
        XCTAssertTrue(didShowNoSpeech)
        XCTAssertTrue(typingService.outputs.isEmpty)
    }

    func testCancelDuringRecordingReturnsToIdle() {
        XCTAssertTrue(coordinator.start())
        coordinator.cancel()

        XCTAssertTrue(coordinator.isIdle)
        XCTAssertTrue(audioCapture.didStop)
        XCTAssertEqual(mediaPlaybackService.resumeCallCount, 1)
    }

    func testCancelDuringTranscriptionDiscardsResult() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeDelay = .milliseconds(200)
        transcriptionService.transcribeResult = .success("ignored")

        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        XCTAssertTrue(coordinator.isTranscribing)

        coordinator.cancel()
        XCTAssertTrue(coordinator.isIdle)

        // Give the cancelled task time to finish and verify it did not output.
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(typingService.outputs.isEmpty)
    }

    func testCancelDuringTranscriptionReleasesActivitySlot() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeDelay = .milliseconds(500)
        transcriptionService.transcribeResult = .success("ignored")

        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        XCTAssertTrue(coordinator.isTranscribing)

        coordinator.cancel()
        XCTAssertTrue(coordinator.isIdle)
        // The activity slot must be released immediately by cancel() so a new
        // session can start without waiting for the (uncancellable) background
        // inference to finish. This is the cancel-activity-leak regression.
        XCTAssertTrue(coordinator.canStart)

        // Let the abandoned task finish so it does not outlive tearDown.
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(typingService.outputs.isEmpty)
    }

    func testAudioConversionErrorIsForwarded() {
        let conversionError = AudioCaptureError.conversionFailed(NSError(domain: "test", code: 1))

        var reportedError: Error?
        coordinator.onAudioConversionError = { error in
            reportedError = error
        }

        XCTAssertTrue(coordinator.start())
        audioCapture.onConversionError?(conversionError)

        XCTAssertNotNil(reportedError)
    }

    func testTranscriptionErrorIsForwarded() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .failure(NSError(domain: "test", code: 42))

        var reportedError: Error?
        coordinator.onTranscriptionError = { error in
            reportedError = error
        }

        let idleExpectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                idleExpectation.fulfill()
            }
        }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        await fulfillment(of: [idleExpectation], timeout: 1.0)
        XCTAssertNotNil(reportedError)
    }

    private func makeLoudSamples() -> [Float] {
        let sampleCount = 16_000
        let amplitude: Float = 0.05
        let frequency = 220.0
        let sampleRate = 16_000.0

        return (0 ..< sampleCount).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            return amplitude * Float(sin(phase))
        }
    }
}

// MARK: - Fakes

final class FakeAudioCapture: AudioCaptureProtocol, @unchecked Sendable {
    var onAudioLevel: ((Float) -> Void)?
    var onConversionError: ((Error) -> Void)?

    var startShouldSucceed = true
    var startError: Error?
    var storedSamples: [Float] = []

    private(set) var didStart = false
    private(set) var didStop = false

    func startCapture() throws {
        guard startShouldSucceed else {
            throw startError ?? AudioCaptureError.invalidFormat
        }
        didStart = true
    }

    func stopCapture() {
        didStop = true
    }

    func currentSamples() -> [Float] {
        storedSamples
    }
}

final class FakeTranscriptionService: TranscriptionProtocol, @unchecked Sendable {
    nonisolated let isReady: Bool = true

    enum Call: Equatable {
        case streaming
        case streamingFinished
        case final
    }

    private let lock = NSLock()
    private var _supportsStreamingTranscription = true
    private var _vocabularyPrompt: String?
    private var _language: String?
    private var _streamingResult: Result<String, Error> = .success("")
    private var _transcribeResult: Result<String, Error> = .success("")
    private var _streamingDelay: Duration?
    private var _transcribeDelay: Duration?
    private var _currentModelID: String? = AppMode.baseModelId
    private var _streamingSampleCounts: [Int] = []
    private var _callOrder: [Call] = []
    private var _holdStreamingUntilReleased = false
    private var _streamingRelease: CheckedContinuation<Void, Never>?
    private var _onStreamingStarted: (() -> Void)?

    var supportsStreamingTranscription: Bool {
        get { lock.withLock { _supportsStreamingTranscription } }
        set { lock.withLock { _supportsStreamingTranscription = newValue } }
    }

    var vocabularyPrompt: String? {
        get { lock.withLock { _vocabularyPrompt } }
        set { lock.withLock { _vocabularyPrompt = newValue } }
    }

    var language: String? {
        get { lock.withLock { _language } }
        set { lock.withLock { _language = newValue } }
    }

    var streamingResult: Result<String, Error> {
        get { lock.withLock { _streamingResult } }
        set { lock.withLock { _streamingResult = newValue } }
    }

    var transcribeResult: Result<String, Error> {
        get { lock.withLock { _transcribeResult } }
        set { lock.withLock { _transcribeResult = newValue } }
    }

    var streamingDelay: Duration? {
        get { lock.withLock { _streamingDelay } }
        set { lock.withLock { _streamingDelay = newValue } }
    }

    var transcribeDelay: Duration? {
        get { lock.withLock { _transcribeDelay } }
        set { lock.withLock { _transcribeDelay = newValue } }
    }

    var currentModelID: String? {
        get { lock.withLock { _currentModelID } }
        set { lock.withLock { _currentModelID = newValue } }
    }

    var streamingSampleCounts: [Int] {
        lock.withLock { _streamingSampleCounts }
    }

    var callOrder: [Call] {
        lock.withLock { _callOrder }
    }

    var onStreamingStarted: (() -> Void)? {
        get { lock.withLock { _onStreamingStarted } }
        set { lock.withLock { _onStreamingStarted = newValue } }
    }

    var holdStreamingUntilReleased: Bool {
        get { lock.withLock { _holdStreamingUntilReleased } }
        set { lock.withLock { _holdStreamingUntilReleased = newValue } }
    }

    func setVocabularyPrompt(_ prompt: String) async {
        vocabularyPrompt = prompt
    }

    func setLanguage(_ language: String) async {
        self.language = language
    }

    func currentModelId() async -> String? {
        currentModelID
    }

    func transcribeStreaming(samples: [Float]) async throws -> String {
        let state = lock.withLock {
            _callOrder.append(.streaming)
            _streamingSampleCounts.append(samples.count)
            return (
                delay: _streamingDelay,
                result: _streamingResult,
                holdStreamingUntilReleased: _holdStreamingUntilReleased,
                onStreamingStarted: _onStreamingStarted
            )
        }

        if state.holdStreamingUntilReleased {
            await withCheckedContinuation { continuation in
                let onStreamingStarted = lock.withLock {
                    _streamingRelease = continuation
                    return _onStreamingStarted
                }
                onStreamingStarted?()
            }
        } else {
            state.onStreamingStarted?()
        }

        if let delay = state.delay {
            try await Task.sleep(for: delay)
        }

        lock.withLock {
            _callOrder.append(.streamingFinished)
        }
        return try state.result.get()
    }

    func releaseStreaming() {
        let continuation = lock.withLock {
            let continuation = _streamingRelease
            _streamingRelease = nil
            return continuation
        }
        continuation?.resume()
    }

    func transcribe(samples: [Float]) async throws -> String {
        lock.withLock {
            _callOrder.append(.final)
        }
        if let delay = transcribeDelay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        return try transcribeResult.get()
    }
}

final class FakeTypingService: OutputProtocol, @unchecked Sendable {
    private(set) var outputs: [String] = []
    private(set) var targetProcessIDs: [pid_t?] = []

    func output(_ text: String, targetProcessID: pid_t?) {
        outputs.append(text)
        targetProcessIDs.append(targetProcessID)
    }
}

final class FakeMediaPlaybackService: MediaPlaybackProtocol, @unchecked Sendable {
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0

    func pauseForDictationIfNeeded() {
        pauseCallCount += 1
    }

    func resumeAfterDictationIfNeeded() {
        resumeCallCount += 1
    }
}

final class FakeDictationHistoryStore: DictationHistoryProtocol, @unchecked Sendable {
    private(set) var sessions: [DictationHistorySession] = []

    func saveSession(_ session: DictationHistorySession) async {
        sessions.append(session)
    }
}
