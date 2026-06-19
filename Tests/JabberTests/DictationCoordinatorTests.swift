import XCTest
@testable import Jabber

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    private var audioCapture: FakeAudioCapture!
    private var transcriptionService: FakeTranscriptionService!
    private var outputManager: FakeOutputManager!
    private var coordinator: DictationCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        audioCapture = FakeAudioCapture()
        transcriptionService = FakeTranscriptionService()
        outputManager = FakeOutputManager()
        coordinator = DictationCoordinator(
            audioCapture: audioCapture,
            transcriptionService: transcriptionService,
            outputManager: outputManager
        )
    }

    override func tearDown() async throws {
        coordinator = nil
        audioCapture = nil
        transcriptionService = nil
        outputManager = nil
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
    }

    func testStopWithoutSpeechReturnsToIdle() {
        XCTAssertTrue(coordinator.start())
        coordinator.stop()

        XCTAssertTrue(coordinator.isIdle)
        XCTAssertTrue(audioCapture.didStop)
        XCTAssertTrue(outputManager.outputs.isEmpty)
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
        XCTAssertEqual(outputManager.outputs, ["hello world"])
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
        XCTAssertTrue(outputManager.outputs.isEmpty)
    }

    func testCancelDuringRecordingReturnsToIdle() {
        XCTAssertTrue(coordinator.start())
        coordinator.cancel()

        XCTAssertTrue(coordinator.isIdle)
        XCTAssertTrue(audioCapture.didStop)
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
        XCTAssertTrue(outputManager.outputs.isEmpty)
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

    private let lock = NSLock()
    private var _vocabularyPrompt: String?
    private var _language: String?
    private var _transcribeResult: Result<String, Error> = .success("")
    private var _transcribeDelay: Duration?

    var vocabularyPrompt: String? {
        get { lock.withLock { _vocabularyPrompt } }
        set { lock.withLock { _vocabularyPrompt = newValue } }
    }

    var language: String? {
        get { lock.withLock { _language } }
        set { lock.withLock { _language = newValue } }
    }

    var transcribeResult: Result<String, Error> {
        get { lock.withLock { _transcribeResult } }
        set { lock.withLock { _transcribeResult = newValue } }
    }

    var transcribeDelay: Duration? {
        get { lock.withLock { _transcribeDelay } }
        set { lock.withLock { _transcribeDelay = newValue } }
    }

    func setVocabularyPrompt(_ prompt: String) async {
        vocabularyPrompt = prompt
    }

    func setLanguage(_ language: String) async {
        self.language = language
    }

    func transcribe(samples: [Float]) async throws -> String {
        if let delay = transcribeDelay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        return try transcribeResult.get()
    }
}

final class FakeOutputManager: OutputProtocol, @unchecked Sendable {
    private(set) var outputs: [String] = []

    func output(_ text: String) {
        outputs.append(text)
    }
}
