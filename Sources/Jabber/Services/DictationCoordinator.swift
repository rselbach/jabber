import Foundation
import os

/// Abstraction over the audio capture pipeline so the coordinator can be tested
/// without accessing the real microphone hardware.
@MainActor
protocol AudioCaptureProtocol: AnyObject {
    var onAudioLevel: ((Float) -> Void)? { get set }
    var onConversionError: ((Error) -> Void)? { get set }
    func startCapture() throws
    func stopCapture()
    func currentSamples() -> [Float]
}

extension AudioCaptureService: AudioCaptureProtocol {}

/// Abstraction over the transcription engine so the coordinator can be tested
/// without loading a real MLX model.
protocol TranscriptionProtocol: AnyObject, Sendable {
    var isReady: Bool { get }
    var supportsStreamingTranscription: Bool { get }
    func setVocabularyPrompt(_ prompt: String) async
    func setLanguage(_ language: String) async
    func currentModelId() async -> String?
    func transcribeStreaming(samples: [Float]) async throws -> String
    func resetStreamingTranscription() async
    func transcribe(samples: [Float]) async throws -> String
}

extension TranscriptionService: TranscriptionProtocol {}

/// Abstraction over text output so the coordinator can be tested without
/// touching the real clipboard or accessibility APIs.
@MainActor
protocol OutputProtocol: AnyObject {
    func output(_ text: String, targetProcessID: pid_t?)
}

extension TypingService: OutputProtocol {}

@MainActor
protocol MediaPlaybackProtocol: AnyObject {
    func pauseForDictationIfNeeded()
    func resumeAfterDictationIfNeeded()
}

/// Owns the entire dictation lifecycle: recording, speech detection,
/// transcription, and output. All state changes are serialized on the main
/// actor and announced through `onStateChange`.
@MainActor
final class DictationCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case transcribing(sessionID: UUID)
    }

    private(set) var state: State = .idle

    var isIdle: Bool {
        state == .idle
    }

    var canStart: Bool {
        state == .idle && !activity.isActive
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = state { return true }
        return false
    }

    var onStateChange: ((State) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onPartialTranscription: ((String) -> Void)?
    var onAudioConversionError: ((Error) -> Void)?
    var onNoSpeechDetected: (() -> Void)?
    var onTranscriptionError: ((Error) -> Void)?
    /// Invoked when post-processing begins, so the overlay can switch to a
    /// "Refining..." label. Not invoked when post-processing is disabled.
    var onRefining: (() -> Void)?
    /// Invoked when post-processing fails (provider throws or returns empty).
    /// Distinct from `onTranscriptionError` so the raw transcript still types
    /// out without a blocking "Transcription Failed" message.
    var onPostProcessingError: ((Error) -> Void)?

    private let audioCapture: any AudioCaptureProtocol
    private let transcriptionService: any TranscriptionProtocol
    private let typingService: any OutputProtocol
    private let mediaPlaybackService: any MediaPlaybackProtocol
    private let dictationHistoryStore: any DictationHistoryProtocol
    private let postProcessingProvider: (any PostProcessingProvider)?
    private var activity = TranscriptionActivityTracker()
    private var transcriptionTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var currentSessionID: UUID?
    private var currentTargetProcessID: pid_t?
    private var lastStreamingPreviewSampleCount = 0
    private var lastStreamingPreviewText = ""
    private let streamingPreviewInterval: Duration
    private let minimumStreamingPreviewSampleCount: Int
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "DictationCoordinator")

    init(
        audioCapture: any AudioCaptureProtocol,
        transcriptionService: any TranscriptionProtocol,
        typingService: any OutputProtocol,
        mediaPlaybackService: any MediaPlaybackProtocol = MediaPlaybackService.shared,
        dictationHistoryStore: any DictationHistoryProtocol = DictationHistoryStore.shared,
        postProcessingProvider: (any PostProcessingProvider)? = AppleIntelligencePostProcessor(),
        streamingPreviewInterval: Duration = .milliseconds(500),
        minimumStreamingPreviewSampleCount: Int = 16_000
    ) {
        self.audioCapture = audioCapture
        self.transcriptionService = transcriptionService
        self.typingService = typingService
        self.mediaPlaybackService = mediaPlaybackService
        self.dictationHistoryStore = dictationHistoryStore
        self.postProcessingProvider = postProcessingProvider
        self.streamingPreviewInterval = streamingPreviewInterval
        self.minimumStreamingPreviewSampleCount = minimumStreamingPreviewSampleCount

        self.audioCapture.onAudioLevel = { [weak self] level in
            self?.onAudioLevel?(level)
        }
        self.audioCapture.onConversionError = { [weak self] error in
            self?.onAudioConversionError?(error)
        }
    }

    /// Starts a new dictation session if the coordinator is idle.
    /// Returns `true` if recording began, `false` otherwise.
    @discardableResult
    func start(targetProcessID: pid_t? = nil) -> Bool {
        guard canStart else { return false }

        let sessionID = UUID()
        currentSessionID = sessionID
        currentTargetProcessID = targetProcessID

        mediaPlaybackService.pauseForDictationIfNeeded()

        do {
            try audioCapture.startCapture()
            state = .recording
            onStateChange?(.recording)
            startStreamingPreview(sessionID: sessionID)
            return true
        } catch {
            logger.error("Failed to start audio capture: \(error.localizedDescription)")
            currentSessionID = nil
            currentTargetProcessID = nil
            mediaPlaybackService.resumeAfterDictationIfNeeded()
            onTranscriptionError?(error)
            return false
        }
    }

    /// Stops recording and, if speech was detected, begins transcription.
    func stop() {
        guard case .recording = state, let sessionID = currentSessionID else { return }

        audioCapture.stopCapture()

        let samples = audioCapture.currentSamples()
        let pendingStreamingTask = stopStreamingPreview()
        let speechAssessment = AudioSpeechDetector.assess(samples: samples)

        guard speechAssessment.shouldTranscribe else {
            if speechAssessment.shouldShowNoSpeechWarning {
                onNoSpeechDetected?()
            }
            finish(sessionID: sessionID)
            return
        }

        guard activity.start(sessionID) else {
            logger.error("Could not mark transcription activity active for session \(sessionID.uuidString)")
            finish(sessionID: sessionID)
            return
        }

        state = .transcribing(sessionID: sessionID)
        onStateChange?(.transcribing(sessionID: sessionID))

        transcriptionTask = Task { [weak self] in
            if let pendingStreamingTask {
                await pendingStreamingTask.value
            }
            await self?.transcribeAndOutput(samples: samples, sessionID: sessionID)
        }
    }

    /// Cancels the current session immediately. Any in-flight transcription
    /// task will finish in the background but will not update state.
    func cancel() {
        guard state != .idle || activity.isActive else { return }

        audioCapture.stopCapture()

        // Invalidate the session so stale transcription tasks cannot touch state.
        let sessionID = currentSessionID
        currentSessionID = nil
        currentTargetProcessID = nil
        _ = stopStreamingPreview()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Release the activity slot immediately so a cancelled-in-flight
        // transcription does not block new sessions while the (uncancellable)
        // background inference keeps running. The task's `defer` will call
        // `activity.complete(sessionID)` again, but that is a no-op once the
        // active id has been cleared here.
        if activity.isActive, let sessionID {
            _ = activity.complete(sessionID)
        }

        if state != .idle {
            state = .idle
            onStateChange?(.idle)
        }
        mediaPlaybackService.resumeAfterDictationIfNeeded()
    }

    private func startStreamingPreview(sessionID: UUID) {
        guard transcriptionService.supportsStreamingTranscription else { return }

        _ = stopStreamingPreview()
        lastStreamingPreviewSampleCount = 0
        lastStreamingPreviewText = ""

        streamingTask = Task { [weak self] in
            await self?.runStreamingPreviewLoop(sessionID: sessionID)
        }
    }

    private func stopStreamingPreview() -> Task<Void, Never>? {
        let task = streamingTask
        streamingTask = nil
        task?.cancel()
        return task
    }

    private func runStreamingPreviewLoop(sessionID: UUID) async {
        await transcriptionService.resetStreamingTranscription()
        await applyCurrentTranscriptionSettings()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: streamingPreviewInterval)
            } catch is CancellationError {
                break
            } catch {
                logger.error("Streaming preview sleep failed: \(error.localizedDescription)")
                break
            }

            guard !Task.isCancelled else { break }
            guard currentSessionID == sessionID, state == .recording else { break }
            await publishStreamingPreviewIfAvailable(sessionID: sessionID)
        }
    }

    private func publishStreamingPreviewIfAvailable(sessionID: UUID) async {
        let samples = audioCapture.currentSamples()
        guard samples.count >= minimumStreamingPreviewSampleCount else { return }
        guard samples.count > lastStreamingPreviewSampleCount else { return }
        guard AudioSpeechDetector.assess(samples: samples).shouldTranscribe else { return }

        do {
            let text = try await transcriptionService.transcribeStreaming(samples: samples)
            try Task.checkCancellation()

            guard currentSessionID == sessionID, state == .recording else { return }

            lastStreamingPreviewSampleCount = samples.count
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty, trimmedText != lastStreamingPreviewText else { return }

            lastStreamingPreviewText = trimmedText
            onPartialTranscription?(trimmedText)
        } catch is CancellationError {
            // Expected when recording stops while a preview pass is in flight.
        } catch {
            logger.warning("Streaming preview failed: \(error.localizedDescription)")
        }
    }

    private func transcribeAndOutput(samples: [Float], sessionID: UUID) async {
        defer {
            _ = activity.complete(sessionID)
            transcriptionTask = nil
            finish(sessionID: sessionID)
        }

        do {
            try Task.checkCancellation()

            await applyCurrentTranscriptionSettings()

            try Task.checkCancellation()

            let text = try await transcriptionService.transcribe(samples: samples)

            try Task.checkCancellation()
            guard currentSessionID == sessionID else {
                throw CancellationError()
            }

            // Capture the target PID before the awaits below. cancel() mutates
            // currentTargetProcessID (and may start a new session), so reading it
            // later would risk typing stale text into the wrong target.
            let targetProcessID = currentTargetProcessID

            let modelID = await transcriptionService.currentModelId() ?? TypedSettings[.selectedModel]
            let language = TypedSettings[.selectedLanguage]

            let postProcessingOutcome = try await applyPostProcessing(to: text)

            // Re-validate before saving/typing: the awaits above
            // (currentModelId, post-processing) are uncancellable on device.
            // If cancel() invalidated this session mid-flight, abandon output.
            guard currentSessionID == sessionID else {
                throw CancellationError()
            }

            await dictationHistoryStore.saveSession(DictationHistorySession(
                samples: samples,
                transcript: postProcessingOutcome.finalText,
                modelID: modelID,
                language: language,
                rawTranscript: postProcessingOutcome.rawTranscript,
                wasPostProcessed: postProcessingOutcome.wasPostProcessed,
                postProcessingErrorDescription: postProcessingOutcome.errorDescription
            ))

            let trimmedText = postProcessingOutcome.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                typingService.output(trimmedText, targetProcessID: targetProcessID)
            } else if postProcessingOutcome.wasPostProcessed {
                // Post-processor returned empty on success (e.g. "scratch that",
                // "cancel", "never mind"). This is a valid cancellation: type
                // nothing and show no no-speech warning, since speech *was*
                // detected and processed.
                logger.info("Post-processing produced an empty result; treating as user cancellation")
            } else {
                onNoSpeechDetected?()
            }
        } catch is CancellationError {
            // Expected when cancel() is called.
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            onTranscriptionError?(error)
        }
    }

    private func applyCurrentTranscriptionSettings() async {
        let vocab = TypedSettings[.vocabularyPrompt]
        await transcriptionService.setVocabularyPrompt(vocab)

        let language = TypedSettings[.selectedLanguage]
        await transcriptionService.setLanguage(language)
    }

    /// Result of the post-processing step. `outputText` is what gets typed;
    /// `finalText` is what gets stored as the entry's transcript.
    private struct PostProcessingOutcome {
        var finalText: String
        var outputText: String
        var rawTranscript: String?
        var wasPostProcessed: Bool
        var errorDescription: String?
    }

    /// Runs the Apple Intelligence post-processor over `rawText` when enabled
    /// and available. On any provider *failure* (the provider throws) it falls
    /// back to the raw transcript and surfaces the error via
    /// `onPostProcessingError`. A provider *success* that returns empty/
    /// whitespace (e.g. the user said "scratch that" / "cancel") is a valid
    /// cancelled result: nothing is typed and no error is surfaced.
    /// Cancellation is rethrown so the surrounding task unwinds without saving
    /// history or typing output.
    private func applyPostProcessing(to rawText: String) async throws -> PostProcessingOutcome {
        let rawTrimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard TypedSettings[.postProcessingEnabled],
              !rawTrimmed.isEmpty,
              let provider = postProcessingProvider else {
            return PostProcessingOutcome(
                finalText: rawText,
                outputText: rawText,
                rawTranscript: nil,
                wasPostProcessed: false,
                errorDescription: nil
            )
        }

        guard provider.isAvailable else {
            // Apple Intelligence not ready / not enabled / unsupported device.
            // Logged but not surfaced as a user notification — it is a steady
            // OS state that would spam every dictation otherwise. The metadata
            // is still recorded so users can see why nothing was refined.
            logger.info("Post-processing enabled but provider unavailable; using raw transcript")
            return PostProcessingOutcome(
                finalText: rawText,
                outputText: rawText,
                rawTranscript: nil,
                wasPostProcessed: false,
                errorDescription: "Apple Intelligence unavailable"
            )
        }

        onRefining?()

        do {
            try Task.checkCancellation()
            let processed = try await provider.process(rawText)
            // A post-processed empty/whitespace result is a VALID outcome, not a
            // failure: the model may produce it by honoring a full self-correction
            // ("scratch that", "cancel", "never mind"). Normalize whitespace-only
            // to "" and report a successful (cancelled) result. Only a thrown
            // error falls back to the raw transcript.
            let normalized = processed.trimmingCharacters(in: .whitespacesAndNewlines)
            return PostProcessingOutcome(
                finalText: normalized,
                outputText: normalized,
                rawTranscript: rawText,
                wasPostProcessed: true,
                errorDescription: nil
            )
        } catch is CancellationError {
            // Re-throw cancellation so the caller's catch unwinds the task.
            throw CancellationError()
        } catch {
            logger.error("Post-processing failed, falling back to raw transcript: \(error.localizedDescription)")
            onPostProcessingError?(error)
            return PostProcessingOutcome(
                finalText: rawText,
                outputText: rawText,
                rawTranscript: nil,
                wasPostProcessed: false,
                errorDescription: error.localizedDescription
            )
        }
    }

    private func finish(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        currentSessionID = nil
        currentTargetProcessID = nil
        transcriptionTask = nil
        state = .idle
        onStateChange?(.idle)
        mediaPlaybackService.resumeAfterDictationIfNeeded()
    }
}
