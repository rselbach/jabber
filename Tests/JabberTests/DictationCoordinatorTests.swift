import XCTest
@testable import Jabber

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    private var audioCapture: FakeAudioCapture!
    private var transcriptionService: FakeTranscriptionService!
    private var typingService: FakeTypingService!
    private var mediaPlaybackService: FakeMediaPlaybackService!
    private var dictationHistoryStore: FakeDictationHistoryStore!
    private var postProcessor: FakePostProcessingProvider!
    private var coordinator: DictationCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        audioCapture = FakeAudioCapture()
        transcriptionService = FakeTranscriptionService()
        typingService = FakeTypingService()
        mediaPlaybackService = FakeMediaPlaybackService()
        dictationHistoryStore = FakeDictationHistoryStore()
        postProcessor = FakePostProcessingProvider()
        UserDefaults.standard.removeObject(forKey: AppSettingKey.postProcessingEnabled)
        UserDefaults.standard.removeObject(forKey: AppSettingKey.replacementEntries)
        coordinator = DictationCoordinator(
            audioCapture: audioCapture,
            transcriptionService: transcriptionService,
            typingService: typingService,
            mediaPlaybackService: mediaPlaybackService,
            dictationHistoryStore: dictationHistoryStore,
            postProcessingProvider: postProcessor,
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
        postProcessor = nil
        UserDefaults.standard.removeObject(forKey: AppSettingKey.postProcessingEnabled)
        UserDefaults.standard.removeObject(forKey: AppSettingKey.replacementEntries)
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
        transcriptionService.currentModelID = AppMode.qwen3ModelId
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
        XCTAssertEqual(dictationHistoryStore.sessions[0].modelID, AppMode.qwen3ModelId)
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
        XCTAssertEqual(transcriptionService.resetStreamingCallCount, 1)
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
        XCTAssertEqual(transcriptionService.resetStreamingCallCount, 0)
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

        let noOutput = expectation(description: "no output after cancel")
        noOutput.isInverted = true
        typingService.onOutput = { _ in noOutput.fulfill() }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        XCTAssertTrue(coordinator.isTranscribing)

        coordinator.cancel()
        XCTAssertTrue(coordinator.isIdle)

        await fulfillment(of: [noOutput], timeout: 1.0)
        XCTAssertTrue(typingService.outputs.isEmpty)
    }

    func testCancelDuringTranscriptionReleasesActivitySlot() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeDelay = .milliseconds(500)
        transcriptionService.transcribeResult = .success("ignored")

        let noOutput = expectation(description: "no output after cancel")
        noOutput.isInverted = true
        typingService.onOutput = { _ in noOutput.fulfill() }

        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        XCTAssertTrue(coordinator.isTranscribing)

        coordinator.cancel()
        XCTAssertTrue(coordinator.isIdle)
        // The activity slot must be released immediately by cancel() so a new
        // session can start without waiting for the (uncancellable) background
        // inference to finish. This is the cancel-activity-leak regression.
        XCTAssertTrue(coordinator.canStart)

        await fulfillment(of: [noOutput], timeout: 1.0)
        XCTAssertTrue(typingService.outputs.isEmpty)
    }

    func testCancelDuringPostProcessingDiscardsResult() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        postProcessor.result = .success("Troy Barnes")
        // Park process() on a continuation so cancel() lands mid-flight, the
        // same way the real uncancellable FoundationModels call would.
        postProcessor.holdUntilReleased = true

        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("troy barnes")

        let processStarted = XCTestExpectation(description: "post-processing started")
        postProcessor.onProcessStarted = { processStarted.fulfill() }

        XCTAssertTrue(coordinator.start(targetProcessID: 12_345))
        coordinator.stop()

        // Wait for transcription to finish and post-processing to park.
        await fulfillment(of: [processStarted], timeout: 1.0)

        // Cancel while post-processing is in flight: this nils the target PID
        // and the session id, mutating coordinator state under the stale task.
        coordinator.cancel()
        XCTAssertTrue(coordinator.isIdle)

        let noOutput = expectation(description: "no output after cancel")
        noOutput.isInverted = true
        typingService.onOutput = { _ in noOutput.fulfill() }

        let noSave = expectation(description: "no history save after cancel")
        noSave.isInverted = true
        dictationHistoryStore.onSaveSession = { _ in noSave.fulfill() }

        // Release the parked (uncancellable) post-processing so the stale task
        // races forward into the save/output section.
        postProcessor.releaseProcess()

        await fulfillment(of: [noOutput, noSave], timeout: 1.0)

        // The stale task must NOT save history or type output after cancel().
        XCTAssertTrue(typingService.outputs.isEmpty)
        XCTAssertTrue(dictationHistoryStore.sessions.isEmpty)
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

    // MARK: - Post-processing

    private func enablePostProcessing() {
        UserDefaults.standard.set(true, forKey: AppSettingKey.postProcessingEnabled)
    }

    func testPostProcessingDisabledDoesNotCallProvider() async {
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(" um hello ")

        let idleExpectation = expectationForIdle()
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertTrue(postProcessor.processCallCount == 0)
        XCTAssertEqual(typingService.outputs, ["um hello"])
        XCTAssertEqual(dictationHistoryStore.sessions.count, 1)
        XCTAssertNil(dictationHistoryStore.sessions[0].rawTranscript)
        XCTAssertFalse(dictationHistoryStore.sessions[0].wasPostProcessed)
    }

    func testPostProcessingEnabledOutputsProcessedTranscript() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        postProcessor.result = .success("Hello.")
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(" um hello ")

        var refiningFired = false
        coordinator.onRefining = { refiningFired = true }

        let idleExpectation = expectationForIdle()
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 1)
        XCTAssertEqual(postProcessor.lastProcessedInput, " um hello ")
        XCTAssertTrue(refiningFired)
        XCTAssertEqual(typingService.outputs, ["Hello."])
        XCTAssertEqual(dictationHistoryStore.sessions.count, 1)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, "Hello.")
        XCTAssertEqual(session.rawTranscript, " um hello ")
        XCTAssertTrue(session.wasPostProcessed)
        XCTAssertNil(session.postProcessingErrorDescription)
    }

    func testPostProcessingProviderThrowsOutputsRawAndSurfacesError() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        struct GreendaleError: Error {}
        postProcessor.result = .failure(GreendaleError())

        var surfacedError: Error?
        coordinator.onPostProcessingError = { error in surfacedError = error }
        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("cool cool cool")
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        // Provider throws are NOT retried (retries are for guardrail rejection).
        XCTAssertEqual(postProcessor.processCallCount, 1)
        XCTAssertEqual(typingService.outputs, ["cool cool cool"])
        XCTAssertNotNil(surfacedError)
        // A true provider failure must not trigger the guardrail-fallback path.
        XCTAssertFalse(fallbackCalled)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, "cool cool cool")
        XCTAssertFalse(session.wasPostProcessed)
        XCTAssertNil(session.rawTranscript)
        XCTAssertNotNil(session.postProcessingErrorDescription)
    }

    func testPostProcessingEmptyResultIsSuccessfulCancel() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        // FluidVoice-style full self-correction ("scratch that" / "cancel")
        // makes the model return empty/whitespace. That is a valid success,
        // not a fallback.
        postProcessor.result = .success("   ")

        var surfacedError: Error?
        coordinator.onPostProcessingError = { error in surfacedError = error }
        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }

        var didShowNoSpeech = false
        coordinator.onNoSpeechDetected = { didShowNoSpeech = true }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("troy and abed")
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 1)
        // No fallback to raw, nothing typed, no error surfaced.
        XCTAssertTrue(typingService.outputs.isEmpty)
        XCTAssertNil(surfacedError)
        XCTAssertFalse(fallbackCalled)
        // No-speech warning must NOT fire: speech was detected and processed,
        // the user just cancelled via a self-correction.
        XCTAssertFalse(didShowNoSpeech)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, "")
        XCTAssertEqual(session.rawTranscript, "troy and abed")
        XCTAssertTrue(session.wasPostProcessed)
        XCTAssertNil(session.postProcessingErrorDescription)
    }

    func testPostProcessingInstructionsContainFluidVoiceCapabilities() {
        // Guards against accidental regressions in the dictation prompt's
        // breadth. Does not assert Apple model output, only that the key
        // FluidVoice-style capabilities are present in the instructions.
        let prompt = AppleIntelligencePostProcessor.instructions
        XCTAssertTrue(prompt.contains("EXECUTE commands"))
        XCTAssertTrue(prompt.contains("scratch that"))
        XCTAssertTrue(prompt.contains("smiley face"))
        XCTAssertTrue(prompt.contains("EXPAND abbreviations"))
        XCTAssertTrue(prompt.contains("CONVERT numbers"))
        // Markdown is now permitted when a command requires it (no blanket ban).
        XCTAssertTrue(prompt.contains("plain text or markdown"))
    }

    func testPostProcessingUnavailableOutputsRawWithoutUserError() async {
        enablePostProcessing()
        postProcessor.isAvailable = false
        postProcessor.result = .success("ignored")

        var surfacedError: Error?
        coordinator.onPostProcessingError = { error in surfacedError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("raw only")
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 0)
        XCTAssertEqual(typingService.outputs, ["raw only"])
        XCTAssertNil(surfacedError)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, "raw only")
        XCTAssertFalse(session.wasPostProcessed)
        XCTAssertEqual(session.postProcessingErrorDescription, "Apple Intelligence unavailable")
    }

    func testPostProcessingSkippedWhenRawTranscriptIsEmpty() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        postProcessor.result = .success("should not happen")

        var didShowNoSpeech = false
        coordinator.onNoSpeechDetected = { didShowNoSpeech = true }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("   ")
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 0)
        XCTAssertTrue(didShowNoSpeech)
        XCTAssertTrue(typingService.outputs.isEmpty)
    }

    // MARK: - Post-processing validation (defense-in-depth)

    func testPostProcessingAggressiveShrinkageFallsBackToRaw() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        // 25-word Greendale transcript with no correction triggers.
        let raw = "Troy and Abed are studying at Greendale Community College for their Spanish exam with Señor Chang and they hope to pass the class this semester."
        // Suspiciously summarized to 3 words (~12% of raw), no markdown. Both
        // the first pass and the retry return this, so both are rejected.
        postProcessor.result = .success("Studying at Greendale.")

        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }
        var providerError: Error?
        coordinator.onPostProcessingError = { error in providerError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(raw)
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        // Guardrail rejection triggers exactly one retry; both passes rejected.
        XCTAssertEqual(postProcessor.processCallCount, 2)
        // Corrupted summary must not be typed; the raw transcript is used.
        XCTAssertEqual(typingService.outputs, [raw])
        // Validation fallback is non-disruptive: the provider-error path (which
        // drives a click-to-dismiss alert) must NOT fire.
        XCTAssertTrue(fallbackCalled)
        XCTAssertNil(providerError)
        let session = dictationHistoryStore.sessions[0]
        // The user-facing localizedDescription must not leak the Swift type
        // name ("Jabber.PostProcessingValidationError error 1.") and must
        // explain the fallback in plain English. History mirrors it.
        let localized = session.postProcessingErrorDescription ?? ""
        XCTAssertFalse(localized.contains("PostProcessingValidationError error"))
        XCTAssertTrue(localized.contains("looked too different"))
        XCTAssertTrue(localized.localizedCaseInsensitiveContains("raw transcript"))
        XCTAssertEqual(session.transcript, raw)
        XCTAssertFalse(session.wasPostProcessed)
        XCTAssertNil(session.rawTranscript)
    }

    func testPostProcessingRogueMarkdownHeadingFallsBackToRaw() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        // 7-word raw (< shrinkageMinimumRawWords, so shrinkage is skipped) and
        // free of any formatting command words.
        let raw = "the trojan horse is a great plan"
        // Provider injected a markdown heading the user never asked for. Both
        // the first pass and the retry return this, so both are rejected.
        postProcessor.result = .success("# The Trojan Horse Is A Great Plan")

        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }
        var providerError: Error?
        coordinator.onPostProcessingError = { error in providerError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(raw)
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 2)
        XCTAssertEqual(typingService.outputs, [raw])
        XCTAssertTrue(fallbackCalled)
        XCTAssertNil(providerError)
        let session = dictationHistoryStore.sessions[0]
        let localized = session.postProcessingErrorDescription ?? ""
        XCTAssertFalse(localized.contains("PostProcessingValidationError error"))
        XCTAssertTrue(localized.contains("Markdown formatting"))
        XCTAssertTrue(localized.localizedCaseInsensitiveContains("raw transcript"))
        XCTAssertEqual(session.transcript, raw)
        XCTAssertFalse(session.wasPostProcessed)
    }

    func testPostProcessingExplicitHeaderCommandAllowsMarkdown() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        // The user explicitly dictated "header", so a leading "#" is
        // intentional and must NOT be treated as rogue markdown.
        let raw = "header shopping list"
        postProcessor.result = .success("# Shopping List")

        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }
        var surfacedError: Error?
        coordinator.onPostProcessingError = { error in surfacedError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(raw)
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        // First pass passes validation, so no retry and no fallback.
        XCTAssertEqual(postProcessor.processCallCount, 1)
        // Processed markdown output is kept because the user requested it.
        XCTAssertEqual(typingService.outputs, ["# Shopping List"])
        XCTAssertFalse(fallbackCalled)
        XCTAssertNil(surfacedError)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, "# Shopping List")
        XCTAssertEqual(session.rawTranscript, raw)
        XCTAssertTrue(session.wasPostProcessed)
        XCTAssertNil(session.postProcessingErrorDescription)
    }

    func testPostProcessingRetrySucceedsOnSecondAttempt() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        // 25-word Greendale transcript with no correction triggers.
        let raw = "Troy and Abed are studying at Greendale Community College for their Spanish exam with Señor Chang and they hope to pass the class this semester."
        // First pass: suspiciously summarized (rejected). Retry: clean output
        // that preserves content, so it passes validation and is typed.
        let cleaned = "Troy and Abed are studying at Greendale Community College for their Spanish exam with Señor Chang, and they hope to pass the class this semester."
        postProcessor.sequentialResults = [
            .success("Studying at Greendale."),
            .success(cleaned)
        ]

        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }
        var providerError: Error?
        coordinator.onPostProcessingError = { error in providerError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(raw)
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        // One rejected pass plus one retry.
        XCTAssertEqual(postProcessor.processCallCount, 2)
        // The retry output is used as the successful post-processed result.
        XCTAssertEqual(typingService.outputs, [cleaned])
        XCTAssertFalse(fallbackCalled)
        XCTAssertNil(providerError)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, cleaned)
        XCTAssertEqual(session.rawTranscript, raw)
        XCTAssertTrue(session.wasPostProcessed)
        XCTAssertNil(session.postProcessingErrorDescription)
    }

    func testPostProcessingRetryThrowFallsBackWithoutDisruptiveAlert() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        // 25-word Greendale transcript with no correction triggers.
        let raw = "Troy and Abed are studying at Greendale Community College for their Spanish exam with Señor Chang and they hope to pass the class this semester."
        struct GreendaleError: Error {}
        // First pass: rejected by guardrails. Retry: provider throws. We were
        // already in a guardrail-fallback scenario, so feedback stays
        // non-disruptive (no provider-error alert).
        postProcessor.sequentialResults = [
            .success("Studying at Greendale."),
            .failure(GreendaleError())
        ]

        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }
        var providerError: Error?
        coordinator.onPostProcessingError = { error in providerError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(raw)
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 2)
        XCTAssertEqual(typingService.outputs, [raw])
        // Validation scenario stays non-disruptive even when the retry throws.
        XCTAssertTrue(fallbackCalled)
        XCTAssertNil(providerError)
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, raw)
        XCTAssertFalse(session.wasPostProcessed)
        XCTAssertNotNil(session.postProcessingErrorDescription)
    }

    func testPostProcessingSampleOverTransformationFallsBackToRaw() async {
        enablePostProcessing()
        postProcessor.isAvailable = true
        let raw = "This is a test of the transcribing capabilities. I am going to say some things and we will see what the result is. Newline. Now I want to see if the commands are working."
        // Observed Apple Intelligence over-transformation: a markdown heading
        // plus heavy summarization of a 34-word transcript down to 7 words.
        // Both passes return this, so both are rejected (shrinkage first).
        postProcessor.result = .success("# Testing Transcription Capabilities\nSee results. Commands: working.")

        var fallbackCalled = false
        coordinator.onPostProcessingFallback = { fallbackCalled = true }
        var providerError: Error?
        coordinator.onPostProcessingError = { error in providerError = error }

        let idleExpectation = expectationForIdle()
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success(raw)
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(postProcessor.processCallCount, 2)
        XCTAssertEqual(typingService.outputs, [raw])
        XCTAssertTrue(fallbackCalled)
        XCTAssertNil(providerError)
        let session = dictationHistoryStore.sessions[0]
        // Shrinkage is checked before markdown, so the over-transformation
        // case surfaces as suspicious shrinkage.
        let localized = session.postProcessingErrorDescription ?? ""
        XCTAssertFalse(localized.contains("PostProcessingValidationError error"))
        XCTAssertTrue(localized.contains("looked too different"))
        XCTAssertTrue(localized.localizedCaseInsensitiveContains("raw transcript"))
        XCTAssertEqual(session.transcript, raw)
        XCTAssertFalse(session.wasPostProcessed)
    }

    // MARK: - Instant replacement (final pass)

    private func enableReplacementEntries(_ entries: [ReplacementEntry]) {
        UserDefaults.standard.set(
            ReplacementEntriesCodec.encode(entries),
            forKey: AppSettingKey.replacementEntries
        )
    }

    func testInstantReplacementAppliedToRawTranscript() async {
        enableReplacementEntries([
            ReplacementEntry(triggers: ["troy barnes"], replacement: "Troy Barnes")
        ])
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("i saw troy barnes at greendale")

        let idleExpectation = expectationForIdle()
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(typingService.outputs, ["i saw Troy Barnes at greendale"])
        XCTAssertEqual(dictationHistoryStore.sessions[0].transcript, "i saw Troy Barnes at greendale")
    }

    func testInstantReplacementAppliedAfterPostProcessing() async {
        enableReplacementEntries([
            ReplacementEntry(triggers: ["troy barnes"], replacement: "Troy Barnes")
        ])
        enablePostProcessing()
        postProcessor.isAvailable = true
        // Post-processing output still contains the literal trigger; the
        // replacement must run AFTER post-processing to catch it.
        postProcessor.result = .success("hello troy barnes")
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("hello troy barnes")

        let idleExpectation = expectationForIdle()
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(typingService.outputs, ["hello Troy Barnes"])
        let session = dictationHistoryStore.sessions[0]
        XCTAssertEqual(session.transcript, "hello Troy Barnes")
        // rawTranscript is the pre-replacement raw input, unchanged.
        XCTAssertEqual(session.rawTranscript, "hello troy barnes")
        XCTAssertTrue(session.wasPostProcessed)
    }

    func testInstantReplacementNoOpWithoutEntries() async {
        // No entries configured: transcript passes through untouched.
        audioCapture.storedSamples = makeLoudSamples()
        transcriptionService.transcribeResult = .success("troy and abed")

        let idleExpectation = expectationForIdle()
        XCTAssertTrue(coordinator.start())
        coordinator.stop()
        await fulfillment(of: [idleExpectation], timeout: 1.0)

        XCTAssertEqual(typingService.outputs, ["troy and abed"])
    }

    private func expectationForIdle() -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "coordinator returns to idle")
        coordinator.onStateChange = { state in
            if state == .idle {
                expectation.fulfill()
            }
        }
        return expectation
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
    private var _currentModelID: String? = AppMode.nemotronModelId
    private var _streamingSampleCounts: [Int] = []
    private var _resetStreamingCallCount = 0
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

    var resetStreamingCallCount: Int {
        lock.withLock { _resetStreamingCallCount }
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

    func resetStreamingTranscription() async {
        lock.withLock {
            _resetStreamingCallCount += 1
        }
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
    var onOutput: ((String) -> Void)?

    func output(_ text: String, targetProcessID: pid_t?) {
        outputs.append(text)
        targetProcessIDs.append(targetProcessID)
        onOutput?(text)
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
    var onSaveSession: ((DictationHistorySession) -> Void)?

    func saveSession(_ session: DictationHistorySession) async {
        sessions.append(session)
        onSaveSession?(session)
    }
}

final class FakePostProcessingProvider: PostProcessingProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _isAvailable = true
    private var _result: Result<String, Error> = .success("")
    private var _sequentialResults: [Result<String, Error>] = []
    private var _sequentialIndex = 0
    private var _processCallCount = 0
    private var _lastProcessedInput: String?
    private var _holdUntilReleased = false
    private var _processRelease: CheckedContinuation<Void, Never>?
    private var _onProcessStarted: (() -> Void)?

    var isAvailable: Bool {
        get { lock.withLock { _isAvailable } }
        set { lock.withLock { _isAvailable = newValue } }
    }

    var result: Result<String, Error> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    /// Per-call results returned in order. When non-empty, each `process(_:)`
    /// call returns the next entry (the last entry is reused past the end) and
    /// `result` is ignored. Used to simulate a first pass that fails
    /// validation followed by a retry that succeeds (or fails again).
    var sequentialResults: [Result<String, Error>] {
        get { lock.withLock { _sequentialResults } }
        set { lock.withLock { _sequentialResults = newValue; _sequentialIndex = 0 } }
    }

    var processCallCount: Int {
        lock.withLock { _processCallCount }
    }

    var lastProcessedInput: String? {
        lock.withLock { _lastProcessedInput }
    }

    var holdUntilReleased: Bool {
        get { lock.withLock { _holdUntilReleased } }
        set { lock.withLock { _holdUntilReleased = newValue } }
    }

    var onProcessStarted: (() -> Void)? {
        get { lock.withLock { _onProcessStarted } }
        set { lock.withLock { _onProcessStarted = newValue } }
    }

    /// Resumes a `process(_:)` call parked via `holdUntilReleased`.
    func releaseProcess() {
        let continuation = lock.withLock {
            let continuation = _processRelease
            _processRelease = nil
            return continuation
        }
        continuation?.resume()
    }

    func process(_ transcript: String) async throws -> String {
        let snapshot = lock.withLock {
            _processCallCount += 1
            _lastProcessedInput = transcript
            let result: Result<String, Error>
            if !_sequentialResults.isEmpty {
                let index = min(_sequentialIndex, _sequentialResults.count - 1)
                result = _sequentialResults[index]
                _sequentialIndex += 1
            } else {
                result = _result
            }
            return (
                result: result,
                holdUntilReleased: _holdUntilReleased,
                onProcessStarted: _onProcessStarted
            )
        }

        if snapshot.holdUntilReleased {
            await withCheckedContinuation { continuation in
                let onProcessStarted = lock.withLock {
                    _processRelease = continuation
                    return _onProcessStarted
                }
                onProcessStarted?()
            }
        } else {
            snapshot.onProcessStarted?()
        }

        return try snapshot.result.get()
    }
}
