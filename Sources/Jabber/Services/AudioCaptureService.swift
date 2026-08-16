@preconcurrency import AVFoundation
@preconcurrency import AudioToolbox
import Foundation
import os

@MainActor
final class AudioCaptureService {
    private var engineStorage: AnyObject?
    private let inputDeviceMonitor = AudioInputDeviceMonitor.shared
    private let targetSampleRate: Double = 16_000
    private let converterQueue = DispatchQueue(label: "com.jabber.audioconverter")
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated private static let initialCapturedSampleCapacity = 16_000 * 60

    nonisolated private let captureState = OSAllocatedUnfairLock(initialState: CaptureState())
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AudioCaptureService")

    private struct CaptureState {
        var lastLevelUpdate: CFAbsoluteTime = 0
        var capturedSamples: [Float] = []
        var isCapturing = false
        var engineGeneration = 0
        var firstBufferGeneration = 0
        /// Set when capture starts, cleared once the tap delivers its first
        /// buffer, so the wait for CoreAudio can be logged exactly once.
        var captureStartedAt: ContinuousClock.Instant?
    }

    private enum InputRebuildReason: Equatable, CustomStringConvertible {
        case defaultDeviceChanged
        case deviceListChanged
        case selectionChanged
        case engineConfigurationChanged
        case missingFirstBuffer

        var description: String {
            switch self {
            case .defaultDeviceChanged:
                return "the default input changed"
            case .deviceListChanged:
                return "the available input devices changed"
            case .selectionChanged:
                return "the selected input changed"
            case .engineConfigurationChanged:
                return "the audio engine configuration changed"
            case .missingFirstBuffer:
                return "the input delivered no audio"
            }
        }
    }

    var onAudioLevel: ((Float) -> Void)?
    var onConversionError: ((Error) -> Void)?
    /// Invoked only when input recovery fails, so the coordinator can stop the
    /// session, preserve captured audio, and surface the failure.
    var onCaptureInterrupted: ((Error) -> Void)?
    private var configurationChangeObserver: (any NSObjectProtocol)?
    /// Engine built, converter created, tap installed. The microphone is only
    /// open once the engine is also running.
    private var isPrepared = false
    /// Set when the audio route changes, so the engine is rebuilt against the
    /// new input device instead of being kept warm in a stale configuration.
    private var needsRebuild = false
    private var standbyTask: Task<Void, Never>?
    private var inputRecoveryTask: Task<Void, Never>?
    private var inputRecoveryGeneration = 0
    private var firstBufferWatchdogTask: Task<Void, Never>?
    private var didRetryMissingFirstBuffer = false
    private var configuredInputDeviceID: AudioDeviceID?
    /// How long the engine keeps running after a session. Back-to-back
    /// dictations then skip the start cost; a lone one releases the
    /// microphone, and its indicator, shortly after.
    private let standbyDuration: Duration = .seconds(8)
    private let firstBufferTimeout: Duration = .seconds(2)
    private let inputReadinessRetryDelay: Duration = .milliseconds(200)
    private let inputReadinessAttempts = 6

    init() {
        captureState.withLock {
            $0.capturedSamples.reserveCapacity(Self.initialCapturedSampleCapacity)
        }
        inputDeviceMonitor.onDefaultInputDeviceChange = { [weak self] in
            guard TypedSettings[.inputDeviceUID].isEmpty else { return }
            self?.requestInputRebuild(reason: .defaultDeviceChanged)
        }
        inputDeviceMonitor.onDeviceListChange = { [weak self] in
            self?.handleDeviceListChange()
        }
        inputDeviceMonitor.onSelectionChange = { [weak self] in
            self?.requestInputRebuild(reason: .selectionChanged)
        }
    }

    private var isCapturing: Bool {
        get { captureState.withLock { $0.isCapturing } }
        set { captureState.withLock { $0.isCapturing = newValue } }
    }

    /// Runs `body` against the converter with exclusive access. The tap and the
    /// end-of-session drain both use it, and since the tap stays installed
    /// between sessions the two can otherwise overlap.
    nonisolated private func withConverter<T>(_ body: (AVAudioConverter) -> T) -> T? {
        converterQueue.sync {
            guard let converter else { return nil }
            return body(converter)
        }
    }

    nonisolated private func setConverter(_ newConverter: AVAudioConverter?) {
        converterQueue.sync { converter = newConverter }
    }

    private func audioEngine() -> AVAudioEngine {
        if let engine = engineStorage as? AVAudioEngine {
            return engine
        }

        let engine = AVAudioEngine()
        engineStorage = engine
        return engine
    }

    /// Builds the engine, converter, and tap ahead of time without opening the
    /// microphone, so a dictation does not pay CoreAudio setup between the
    /// hotkey and the first captured sample. Safe to call repeatedly.
    func prepare() {
        guard !isPrepared, !isCapturing else { return }

        do {
            try buildEngine()
        } catch {
            // Nothing is lost: startCapture() builds on demand and surfaces
            // the failure to the user there.
            logger.warning("Audio capture prepare failed: \(error.localizedDescription)")
        }
    }

    private func buildEngine() throws {
        let engine = audioEngine()
        let inputNode = engine.inputNode
        try configureInputDevice(inputNode)
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // A device that is still waking up reports a zero-rate format; a tap
        // installed against it never delivers audio.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidFormat
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        setConverter(converter)

        let generation = captureState.withLock { state in
            state.engineGeneration += 1
            return state.engineGeneration
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, generation: generation)
        }

        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange()
            }
        }

        engine.prepare()
        isPrepared = true
        needsRebuild = false
    }

    private func configureInputDevice(_ inputNode: AVAudioInputNode) throws {
        let selectedUID = TypedSettings[.inputDeviceUID]
        guard !selectedUID.isEmpty else {
            configuredInputDeviceID = nil
            return
        }
        guard var deviceID = inputDeviceMonitor.deviceID(forUID: selectedUID) else {
            throw AudioCaptureError.selectedInputUnavailable
        }
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureError.inputDeviceSelectionUnavailable
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.couldNotSelectInput(status)
        }
        configuredInputDeviceID = deviceID
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        let startedAt = ContinuousClock.now
        cancelInputRecovery()
        standbyTask?.cancel()
        standbyTask = nil
        didRetryMissingFirstBuffer = false

        if needsRebuild || !isPrepared {
            teardownEngine()
            try buildEngine()
        }

        let engine = audioEngine()
        // Clear the resampler's filter state so the tail drained at the end of
        // the previous session cannot bleed into this one.
        withConverter { $0.reset() }

        captureState.withLock {
            $0.capturedSamples.removeAll(keepingCapacity: true)
            $0.isCapturing = true
            $0.firstBufferGeneration = 0
            $0.captureStartedAt = startedAt
        }

        do {
            if !engine.isRunning {
                try engine.start()
            }
            armFirstBufferWatchdog()
        } catch {
            // Whatever the engine was holding is suspect now; make the next
            // attempt build from scratch rather than reuse it.
            needsRebuild = true
            stopCapture()
            throw error
        }
        logger.notice("Audio capture engine ready in \((ContinuousClock.now - startedAt).wholeMilliseconds) ms")
    }

    private func handleConfigurationChange() {
        requestInputRebuild(reason: .engineConfigurationChanged)
    }

    private func handleDeviceListChange() {
        let selectedUID = TypedSettings[.inputDeviceUID]
        guard !selectedUID.isEmpty else { return }

        let resolvedDeviceID = inputDeviceMonitor.deviceID(forUID: selectedUID)
        guard resolvedDeviceID != configuredInputDeviceID else { return }
        configuredInputDeviceID = resolvedDeviceID
        requestInputRebuild(reason: .deviceListChanged)
    }

    private func requestInputRebuild(reason: InputRebuildReason) {
        needsRebuild = true
        guard isPrepared || isCapturing else {
            logger.notice("Deferring input rebuild until capture is prepared")
            return
        }
        guard inputRecoveryTask == nil else {
            logger.notice("Coalescing input rebuild after \(reason)")
            return
        }
        if reason != .missingFirstBuffer {
            didRetryMissingFirstBuffer = false
        }

        logger.notice("Scheduling input rebuild because \(reason)")
        inputRecoveryGeneration += 1
        let recoveryGeneration = inputRecoveryGeneration
        inputRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rebuildInput(reason: reason, recoveryGeneration: recoveryGeneration)
        }
    }

    private func rebuildInput(reason: InputRebuildReason, recoveryGeneration: Int) async {
        let wasCapturing = isCapturing
        teardownEngine(drainConverterTail: wasCapturing)

        var lastError: Error = AudioCaptureError.invalidFormat
        for attempt in 0 ..< inputReadinessAttempts {
            guard !Task.isCancelled else {
                finishInputRecovery(generation: recoveryGeneration)
                return
            }
            if attempt > 0 {
                do {
                    try await Task.sleep(for: inputReadinessRetryDelay)
                } catch {
                    finishInputRecovery(generation: recoveryGeneration)
                    return
                }
            }

            do {
                try buildEngine()
                if isCapturing {
                    captureState.withLock {
                        $0.captureStartedAt = .now
                    }
                    try audioEngine().start()
                    armFirstBufferWatchdog()
                }
                needsRebuild = false
                finishInputRecovery(generation: recoveryGeneration)
                logger.notice("Rebuilt audio input after \(reason)")
                return
            } catch {
                lastError = error
                logger.warning(
                    "Audio input rebuild attempt \(attempt + 1) failed: \(error.localizedDescription)"
                )
                teardownEngine()
            }
        }

        finishInputRecovery(generation: recoveryGeneration)
        guard wasCapturing, isCapturing else {
            logger.error("Could not prepare audio input after \(reason): \(lastError.localizedDescription)")
            return
        }

        onCaptureInterrupted?(AudioCaptureError.deviceChangeRecoveryFailed(lastError))
    }

    private func cancelInputRecovery() {
        inputRecoveryGeneration += 1
        inputRecoveryTask?.cancel()
        inputRecoveryTask = nil
    }

    private func finishInputRecovery(generation: Int) {
        guard inputRecoveryGeneration == generation else { return }
        inputRecoveryTask = nil
    }

    private func scheduleStandbyRetirement() {
        standbyTask?.cancel()
        standbyTask = Task { [weak self, standbyDuration] in
            do {
                try await Task.sleep(for: standbyDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.retireEngine()
        }
    }

    /// Stops the engine but keeps it built, so the microphone (and its
    /// indicator) is released while a restart stays cheap.
    private func retireEngine() {
        standbyTask = nil
        guard !isCapturing, let engine = engineStorage as? AVAudioEngine, engine.isRunning else { return }
        engine.stop()
        logger.notice("Audio engine stopped after standby")
    }

    private func teardownEngine(drainConverterTail: Bool = false) {
        standbyTask?.cancel()
        standbyTask = nil
        firstBufferWatchdogTask?.cancel()
        firstBufferWatchdogTask = nil

        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
            self.configurationChangeObserver = nil
        }

        if let engine = engineStorage as? AVAudioEngine {
            engine.stop()
            if isPrepared {
                engine.inputNode.removeTap(onBus: 0)
            }
        }
        if drainConverterTail {
            drainConverter()
        }

        setConverter(nil)
        isPrepared = false
        engineStorage = nil
    }

    func stopCapture() {
        let wasCapturing = captureState.withLock { $0.isCapturing }
        guard wasCapturing else { return }

        // Close the session before draining so the still-installed tap stops
        // feeding the converter, then flush its filter-delay tail (a few ms of
        // audio at the end of the utterance) into the session's samples.
        captureState.withLock {
            $0.isCapturing = false
            $0.captureStartedAt = nil
        }
        cancelInputRecovery()
        firstBufferWatchdogTask?.cancel()
        firstBufferWatchdogTask = nil
        drainConverter()

        // The engine stays built either way. A route change invalidated the
        // tap, so rebuild now rather than keeping a stale one warm.
        guard !needsRebuild else {
            teardownEngine()
            prepare()
            return
        }
        scheduleStandbyRetirement()
    }

    private func drainConverter() {
        let samples = withConverter { converter -> [Float] in
            // The sample-rate conversion tail is a fixed few milliseconds; 4096
            // frames at 16kHz is far more than any real filter delay.
            guard let tailBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: 4096
            ) else { return [] }

            var error: NSError?
            converter.convert(to: tailBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            if let error {
                logger.warning("Draining audio converter tail failed: \(error.localizedDescription)")
                return []
            }

            guard let channelData = tailBuffer.floatChannelData?[0] else { return [] }
            let frames = Int(tailBuffer.frameLength)
            guard frames > 0 else { return [] }

            return Array(UnsafeBufferPointer(start: channelData, count: frames))
        }

        guard let samples, !samples.isEmpty else { return }
        captureState.withLock {
            $0.capturedSamples.append(contentsOf: samples)
        }
    }

    func currentSamples() -> [Float] {
        captureState.withLock {
            $0.capturedSamples
        }
    }

    /// Number of captured samples without copying the buffer. Cheap, for
    /// callers that only need to know whether new audio arrived (e.g. the
    /// streaming preview's "skip when unchanged" guard).
    func sampleCount() -> Int {
        captureState.withLock {
            $0.capturedSamples.count
        }
    }

    private func armFirstBufferWatchdog() {
        firstBufferWatchdogTask?.cancel()
        let generation = captureState.withLock { $0.engineGeneration }
        firstBufferWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: firstBufferTimeout)
            } catch {
                return
            }

            let isStillMissing = captureState.withLock { state in
                state.isCapturing &&
                    state.engineGeneration == generation &&
                    state.firstBufferGeneration != generation
            }
            guard isStillMissing else { return }

            firstBufferWatchdogTask = nil
            guard !didRetryMissingFirstBuffer else {
                logger.error("Audio input delivered no buffers after a fresh engine retry")
                onCaptureInterrupted?(AudioCaptureError.inputUnavailable)
                return
            }

            didRetryMissingFirstBuffer = true
            logger.warning("Audio input delivered no buffers; rebuilding the engine once")
            requestInputRebuild(reason: .missingFirstBuffer)
        }
    }

    private func didReceiveFirstBuffer(generation: Int) {
        let isCurrentGeneration = captureState.withLock {
            $0.engineGeneration == generation && $0.firstBufferGeneration == generation
        }
        guard isCurrentGeneration else { return }

        firstBufferWatchdogTask?.cancel()
        firstBufferWatchdogTask = nil
    }

    nonisolated private func processBuffer(_ buffer: AVAudioPCMBuffer, generation: Int) {
        // The tap keeps firing while the engine idles in standby; drop those
        // buffers rather than resampling audio no session asked for.
        guard captureState.withLock({
            $0.isCapturing && $0.engineGeneration == generation
        }) else { return }

        let rms = calculateRms(from: buffer)
        let now = CFAbsoluteTimeGetCurrent()
        let shouldReportLevel: Bool = captureState.withLock {
            guard $0.isCapturing else { return false }
            if now - $0.lastLevelUpdate >= 1.0 / 30.0 {
                $0.lastLevelUpdate = now
                return true
            }
            return false
        }
        if shouldReportLevel {
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(rms)
            }
        }

        guard let conversionResult = withConverter({ convertBuffer(buffer, using: $0) }) else { return }
        if let error = conversionResult.error {
            logger.error("Audio conversion failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onConversionError?(AudioCaptureError.conversionFailed(error))
            }
            return
        }

        guard let convertedBuffer = conversionResult.buffer else { return }

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let frames = Int(convertedBuffer.frameLength)
        guard frames > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frames))
        let firstAudio: (delay: Duration, generation: Int)? = captureState.withLock {
            guard $0.isCapturing, $0.engineGeneration == generation else { return nil }
            $0.capturedSamples.append(contentsOf: samples)
            guard $0.firstBufferGeneration != generation else { return nil }
            $0.firstBufferGeneration = generation
            guard let startedAt = $0.captureStartedAt else { return nil }
            $0.captureStartedAt = nil
            return (ContinuousClock.now - startedAt, generation)
        }

        if let firstAudio {
            logger.notice("First audio arrived \(firstAudio.delay.wholeMilliseconds) ms after capture start")
            DispatchQueue.main.async { [weak self] in
                self?.didReceiveFirstBuffer(generation: firstAudio.generation)
            }
        }
    }

    nonisolated private func calculateRms(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        for i in 0 ..< frames {
            sum += channelData[i] * channelData[i]
        }
        return min(1, sqrt(max(0, sum / Float(frames))))
    }

    /// output frame capacity needed to resample `inputFrames` from
    /// `inputRate` to `outputRate`; rounds up so no samples drop and is
    /// floored at one frame to keep downstream buffers non-empty.
    nonisolated static func outputFrameCapacity(
        inputFrames: AVAudioFrameCount,
        inputRate: Double,
        outputRate: Double
    ) -> AVAudioFrameCount {
        let raw = Double(inputFrames) * outputRate / inputRate
        return AVAudioFrameCount(max(1, raw.rounded(.up)))
    }

    nonisolated private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> (buffer: AVAudioPCMBuffer?, error: Error?) {
        // Convert to 16kHz mono
        let outputFormat = converter.outputFormat
        let outputFrameCapacity = Self.outputFrameCapacity(
            inputFrames: buffer.frameLength,
            inputRate: buffer.format.sampleRate,
            outputRate: outputFormat.sampleRate
        )
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return (nil, nil)
        }

        var error: NSError?
        let inputState = AudioConverterInputState()

        // Capture buffer in the conversion callback to avoid race conditions
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            guard inputState.claimBuffer() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        return (convertedBuffer, error)
    }
}

private final class AudioConverterInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasProvidedBuffer = false

    func claimBuffer() -> Bool {
        lock.withLock {
            guard !hasProvidedBuffer else { return false }
            hasProvidedBuffer = true
            return true
        }
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case invalidFormat
    case converterUnavailable
    case conversionFailed(Error)
    case inputUnavailable
    case deviceChangeRecoveryFailed(Error)
    case selectedInputUnavailable
    case inputDeviceSelectionUnavailable
    case couldNotSelectInput(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format configuration"
        case .converterUnavailable:
            return "Audio converter could not be created"
        case .conversionFailed(let error):
            return "Audio conversion failed: \(error.localizedDescription)"
        case .inputUnavailable:
            return "The microphone connected, but did not provide any audio"
        case .deviceChangeRecoveryFailed(let error):
            return "Could not reconnect to the microphone: \(error.localizedDescription)"
        case .selectedInputUnavailable:
            return "The selected microphone is not connected"
        case .inputDeviceSelectionUnavailable:
            return "Jabber could not access audio input device selection"
        case .couldNotSelectInput(let status):
            return "Jabber could not select the microphone (OSStatus \(status))"
        }
    }
}
