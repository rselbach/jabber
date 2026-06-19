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
    func setVocabularyPrompt(_ prompt: String) async
    func setLanguage(_ language: String) async
    func transcribe(samples: [Float]) async throws -> String
}

extension TranscriptionService: TranscriptionProtocol {}

/// Abstraction over text output so the coordinator can be tested without
/// touching the real clipboard or accessibility APIs.
@MainActor
protocol OutputProtocol: AnyObject {
    func output(_ text: String)
}

extension OutputManager: OutputProtocol {}

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
    var onAudioConversionError: ((Error) -> Void)?
    var onNoSpeechDetected: (() -> Void)?
    var onTranscriptionError: ((Error) -> Void)?

    private let audioCapture: any AudioCaptureProtocol
    private let transcriptionService: any TranscriptionProtocol
    private let outputManager: any OutputProtocol
    private var activity = TranscriptionActivityTracker()
    private var transcriptionTask: Task<Void, Never>?
    private var currentSessionID: UUID?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "DictationCoordinator")

    init(
        audioCapture: any AudioCaptureProtocol,
        transcriptionService: any TranscriptionProtocol,
        outputManager: any OutputProtocol
    ) {
        self.audioCapture = audioCapture
        self.transcriptionService = transcriptionService
        self.outputManager = outputManager

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
    func start() -> Bool {
        guard canStart else { return false }

        let sessionID = UUID()
        currentSessionID = sessionID

        do {
            try audioCapture.startCapture()
            state = .recording
            onStateChange?(.recording)
            return true
        } catch {
            logger.error("Failed to start audio capture: \(error.localizedDescription)")
            currentSessionID = nil
            onTranscriptionError?(error)
            return false
        }
    }

    /// Stops recording and, if speech was detected, begins transcription.
    func stop() {
        guard case .recording = state, let sessionID = currentSessionID else { return }

        audioCapture.stopCapture()

        let samples = audioCapture.currentSamples()
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
            await self?.transcribeAndOutput(samples: samples, sessionID: sessionID)
        }
    }

    /// Cancels the current session immediately. Any in-flight transcription
    /// task will finish in the background but will not update state.
    func cancel() {
        guard state != .idle || activity.isActive else { return }

        audioCapture.stopCapture()

        // Invalidate the session so stale transcription tasks cannot touch state.
        currentSessionID = nil
        transcriptionTask?.cancel()
        if !activity.isActive {
            transcriptionTask = nil
        }

        if state != .idle {
            state = .idle
            onStateChange?(.idle)
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

            let vocab = TypedSettings[.vocabularyPrompt]
            await transcriptionService.setVocabularyPrompt(vocab)

            let language = TypedSettings[.selectedLanguage]
            await transcriptionService.setLanguage(language)

            try Task.checkCancellation()

            let text = try await transcriptionService.transcribe(samples: samples)

            try Task.checkCancellation()
            guard currentSessionID == sessionID else {
                throw CancellationError()
            }

            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                outputManager.output(trimmedText)
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

    private func finish(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        currentSessionID = nil
        transcriptionTask = nil
        state = .idle
        onStateChange?(.idle)
    }
}
