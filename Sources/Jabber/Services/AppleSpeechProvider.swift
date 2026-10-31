import AVFoundation
@preconcurrency import AVFAudio
import Foundation
import os
import Speech

final class AppleSpeechProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AppleSpeechProvider")
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var analyzerFormat: AVAudioFormat?
        /// The locale Jabber asked for. Asking for a different one re-prepares.
        var preparedLocale: Locale?
        /// The Apple module that serves `preparedLocale`.
        var transcriber: Transcriber?
        var ready = false
    }

    /// The Apple module that transcribes a locale, and the supported locale it
    /// runs with. SpeechTranscriber is Apple's newer, more accurate model but
    /// covers fewer languages; DictationTranscriber covers the rest of what
    /// system dictation supports.
    enum Transcriber: Equatable {
        case speech(Locale)
        case dictation(Locale)
    }

    var isReady: Bool {
        state.withLock { $0.ready }
    }

    init(modelId: String) {
        self.modelId = modelId
    }

    func load(from cacheDir: URL, progressHandler: (@Sendable (Double, String) -> Void)?) async throws {
        let languageCode = await MainActor.run { TypedSettings[.selectedLanguage] }
        let locale = Self.locale(for: languageCode)

        try await prepareForLocale(locale, progressHandler: progressHandler)
        state.withLock { $0.ready = true }
        progressHandler?(1.0, "Ready")
    }

    /// Picks the Apple module for `locale`, ensures its speech asset is
    /// installed, and rebuilds the converter/analyzerFormat for it. Shared by
    /// `load()` and `transcribe()` so a language switch without a model switch
    /// re-prepares the provider instead of transcribing in the stale locale.
    private func prepareForLocale(
        _ locale: Locale,
        progressHandler: (@Sendable (Double, String) -> Void)?
    ) async throws {
        let transcriber = try await Self.transcriber(for: locale)
        let module = Self.makeModule(transcriber)

        // Nil when the asset is already installed.
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let progress = downloader.progress
            let monitorTask = Task {
                while !Task.isCancelled, !progress.isFinished, !progress.isCancelled {
                    progressHandler?(progress.fractionCompleted, "Downloading speech model...")
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        break
                    }
                }
            }
            defer { monitorTask.cancel() }
            try await downloader.downloadAndInstall()
        }

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        state.withLock {
            $0.analyzerFormat = analyzerFormat
            $0.preparedLocale = locale
            $0.transcriber = transcriber
        }
    }

    /// Prefers SpeechTranscriber and falls back to DictationTranscriber, each
    /// asked for its supported locale equivalent to `locale`.
    static func transcriber(for locale: Locale) async throws -> Transcriber {
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(supported)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(supported)
        }
        throw TranscriptionError.unsupportedLanguage(locale)
    }

    private static func makeModule(_ transcriber: Transcriber) -> any SpeechModule {
        switch transcriber {
        case let .speech(locale):
            makeSpeechTranscriber(locale)
        case let .dictation(locale):
            makeDictationTranscriber(locale)
        }
    }

    private static func makeSpeechTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    private static func makeDictationTranscriber(_ locale: Locale) -> DictationTranscriber {
        // Unlike SpeechTranscriber, dictation punctuates only when asked.
        DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [.punctuation],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        let initialState = state.withLock { $0 }
        guard initialState.ready else { throw TranscriptionError.loadFailed }

        // Prefer the freshly-passed language over the locale captured at load()
        // time. TranscriptionService only reloads when the model id changes, so
        // a language switch without a model switch would otherwise leave Apple
        // Speech transcribing in the old language until app restart. When the
        // resolved locale differs from the one the converter was built for,
        // re-prepare (installing the new locale's asset if needed and
        // rebuilding the audio path) so transcription matches.
        let locale = Self.resolveLocale(language: language, preparedLocale: initialState.preparedLocale)
        if locale != initialState.preparedLocale {
            try await prepareForLocale(locale, progressHandler: nil)
        }
        let (analyzerFormat, transcriber) = state.withLock { ($0.analyzerFormat, $0.transcriber) }
        guard let transcriber else { throw TranscriptionError.loadFailed }

        guard let buffer = Self.makePCMBuffer(from: samples) else {
            throw TranscriptionError.transcriptionFailed
        }

        let convertedBuffer: AVAudioPCMBuffer
        if let analyzerFormat,
           let converter = AVAudioConverter(from: Self.inputFormat, to: analyzerFormat) {
            convertedBuffer = try Self.convert(buffer, with: converter, to: analyzerFormat)
        } else {
            convertedBuffer = buffer
        }

        let finalText = OSAllocatedUnfairLock(initialState: "")
        let module: any SpeechModule
        let resultsTask: Task<Void, any Error>
        switch transcriber {
        case let .speech(locale):
            let speech = Self.makeSpeechTranscriber(locale)
            module = speech
            resultsTask = Self.collectFinalText(from: speech, into: finalText)
        case let .dictation(locale):
            let dictation = Self.makeDictationTranscriber(locale)
            module = dictation
            resultsTask = Self.collectFinalText(from: dictation, into: finalText)
        }

        let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])

        do {
            try await analyzer.start(inputSequence: inputStream)
            continuation.yield(AnalyzerInput(buffer: convertedBuffer))
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await resultsTask.value
        } catch is CancellationError {
            continuation.finish()
            await cancelResultsTask(resultsTask)
            throw CancellationError()
        } catch {
            continuation.finish()
            await cancelResultsTask(resultsTask)
            logger.error("Speech transcription failed: \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed
        }

        return finalText.withLock { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Joins the final results `module` produces, in order, with spaces.
    private static func collectFinalText<Module: SpeechModule>(
        from module: Module,
        into finalText: OSAllocatedUnfairLock<String>
    ) -> Task<Void, any Error> where Module.Result: TranscribedText {
        Task {
            for try await result in module.results where result.isFinal {
                let text = String(result.text.characters)
                finalText.withLock { accumulated in
                    if !accumulated.isEmpty, !text.isEmpty {
                        accumulated += " "
                    }
                    accumulated += text
                }
            }
        }
    }

    private func cancelResultsTask(_ resultsTask: Task<Void, any Error>) async {
        resultsTask.cancel()
        do {
            try await resultsTask.value
        } catch is CancellationError {
            return
        } catch {
            logger.error("Speech transcription results task failed after cancellation: \(error.localizedDescription)")
        }
    }

    func unload() {
        state.withLock {
            $0.ready = false
            $0.preparedLocale = nil
            $0.transcriber = nil
            $0.analyzerFormat = nil
        }
    }

    // MARK: - Locale Resolution

    static let localeMap: [String: String] = [
        "en": "en-US",
        "es": "es-ES",
        "fr": "fr-FR",
        "de": "de-DE",
        "it": "it-IT",
        "ja": "ja-JP",
        "ko": "ko-KR",
        "pt": "pt-BR",
        "zh": "zh-CN",
        "nl": "nl-NL",
        "ru": "ru-RU",
        "tr": "tr-TR",
        "ar": "ar-SA",
        "hi": "hi-IN",
        "th": "th-TH",
        "vi": "vi-VN",
        "pl": "pl-PL",
        "sv": "sv-SE",
        "da": "da-DK",
        "fi": "fi-FI",
        "cs": "cs-CZ",
        "el": "el-GR",
        "hu": "hu-HU",
        "ro": "ro-RO",
        "uk": "uk-UA",
        "id": "id-ID",
        "ms": "ms-MY",
        "yue": "yue-CN",
        "be": "be-BY",
        "bg": "bg-BG",
        "bs": "bs-BA",
        "et": "et-EE",
        "hr": "hr-HR",
        "lt": "lt-LT",
        "lv": "lv-LV",
        "mt": "mt-MT",
        "sk": "sk-SK",
        "sl": "sl-SI",
        "sr": "sr-RS"
    ]

    static func locale(for languageCode: String?) -> Locale {
        let code = languageCode ?? "auto"
        if code == "auto" {
            return Locale.current
        }
        let identifier = localeMap[code] ?? code
        return Locale(identifier: identifier)
    }

    /// Resolves the locale for a transcription call, preferring the freshly
    /// passed `language` over the locale captured at `load()` time. When
    /// `language` is nil (auto-detect), keeps the prepared locale (or falls
    /// back to the current locale) so auto-detect doesn't drift mid-session.
    /// Pure so the decision is testable without the Speech framework.
    static func resolveLocale(language: String?, preparedLocale: Locale?) -> Locale {
        if let language {
            return locale(for: language)
        }
        return preparedLocale ?? locale(for: nil)
    }

    // MARK: - Audio Buffer Helpers

    private static let inputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private static func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                channelData[0].update(from: base, count: samples.count)
            }
        }
        return buffer
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let capacity = AudioCaptureService.outputFrameCapacity(
            inputFrames: buffer.frameLength,
            inputRate: converter.inputFormat.sampleRate,
            outputRate: outputFormat.sampleRate
        )

        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw TranscriptionError.transcriptionFailed
        }

        let processed = OSAllocatedUnfairLock(initialState: false)
        let status = converter.convert(to: output, error: nil) { _, outStatus in
            let alreadyDone = processed.withLock { state -> Bool in
                let wasProcessed = state
                state = true
                return wasProcessed
            }
            if alreadyDone {
                // This converter sees exactly one buffer: signal end-of-stream
                // (not .noDataNow, which promises more input later) so a
                // resampling converter flushes its filter-delay tail instead
                // of dropping the final milliseconds of the utterance.
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else { throw TranscriptionError.transcriptionFailed }
        return output
    }
}

/// The transcribed text both Apple transcribers' results carry, so one
/// collector serves either module.
private protocol TranscribedText {
    var text: AttributedString { get }
}

extension SpeechTranscriber.Result: TranscribedText {}
extension DictationTranscriber.Result: TranscribedText {}
