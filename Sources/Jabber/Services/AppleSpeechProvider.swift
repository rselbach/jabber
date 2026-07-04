import AVFoundation
@preconcurrency import AVFAudio
import Foundation
import os
import Speech

final class AppleSpeechProvider: TranscriptionProvider, @unchecked Sendable {
    let modelId: String

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AppleSpeechProvider")

    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var preparedLocale: Locale?
    private var ready = false

    var isReady: Bool {
        ready
    }

    init(modelId: String) {
        self.modelId = modelId
    }

    func load(from cacheDir: URL, progressHandler: ((Double, String) -> Void)?) async throws {
        let languageCode = await MainActor.run { TypedSettings[.selectedLanguage] }
        let locale = Self.locale(for: languageCode)

        try await prepareForLocale(locale, progressHandler: progressHandler)
        ready = true
        progressHandler?(1.0, "Ready")
    }

    /// Ensures the speech asset for `locale` is installed and rebuilds the
    /// converter/analyzerFormat for it. Shared by `load()` and `transcribe()`
    /// so a language switch without a model switch re-preares the provider
    /// instead of transcribing in the stale locale.
    private func prepareForLocale(
        _ locale: Locale,
        progressHandler: ((Double, String) -> Void)?
    ) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let supportedIDs = await SpeechTranscriber.supportedLocales.map { Self.normalized($0) }
        guard supportedIDs.contains(Self.normalized(locale)) else {
            throw TranscriptionError.loadFailed
        }

        let installedIDs = await SpeechTranscriber.installedLocales.map { Self.normalized($0) }
        if !installedIDs.contains(Self.normalized(locale)) {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let progress = downloader.progress
                // progressHandler's type comes from the TranscriptionProvider protocol as a
                // non-Sendable closure, so it cannot cross a Task boundary by default. It is
                // only invoked from this single monitor Task, preserving the pre-existing
                // timing/behavior, so we opt out of the check here rather than add sync. When
                // transcribe() re-prepares for a new locale it passes nil, making the monitor
                // a no-op loop.
                nonisolated(unsafe) let onProgress = progressHandler
                let monitorTask = Task {
                    while !Task.isCancelled, !progress.isFinished, !progress.isCancelled {
                        onProgress?(progress.fractionCompleted, "Downloading speech model...")
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
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        if let analyzerFormat {
            converter = AVAudioConverter(from: Self.inputFormat, to: analyzerFormat)
        }
        preparedLocale = locale
    }

    func transcribe(samples: [Float], language: String?, vocabularyPrompt: String?) async throws -> String {
        guard ready else { throw TranscriptionError.loadFailed }

        // Prefer the freshly-passed language over the locale captured at load()
        // time. TranscriptionService only reloads when the model id changes, so
        // a language switch without a model switch would otherwise leave Apple
        // Speech transcribing in the old language until app restart. When the
        // resolved locale differs from the one the converter was built for,
        // re-prepare (installing the new locale's asset if needed and
        // rebuilding the audio path) so transcription matches.
        let locale = Self.resolveLocale(language: language, preparedLocale: preparedLocale)
        if locale != preparedLocale {
            try await prepareForLocale(locale, progressHandler: nil)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let buffer = Self.makePCMBuffer(from: samples) else {
            throw TranscriptionError.transcriptionFailed
        }

        let convertedBuffer: AVAudioPCMBuffer
        if let converter, let analyzerFormat {
            convertedBuffer = try Self.convert(buffer, with: converter, to: analyzerFormat)
        } else {
            convertedBuffer = buffer
        }

        let finalText = OSAllocatedUnfairLock(initialState: "")
        let resultsTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finalText.withLock { accumulated in
                        if !accumulated.isEmpty, !text.isEmpty {
                            accumulated += " "
                        }
                        accumulated += text
                    }
                }
            }
        }

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
        ready = false
        preparedLocale = nil
        converter = nil
        analyzerFormat = nil
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
        "fa": "fa-IR",
        "id": "id-ID",
        "ms": "ms-MY",
        "mk": "mk-MK",
        "fil": "fil-PH",
        "yue": "yue-CN"
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

    static func normalized(_ locale: Locale) -> String {
        locale.identifier(.bcp47).replacingOccurrences(of: "_", with: "-")
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
        let ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio.rounded(.up))

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
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else { throw TranscriptionError.transcriptionFailed }
        return output
    }
}
