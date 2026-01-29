import AppKit
import Carbon
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private let hotkeyManager = HotkeyManager()
    private let audioCapture = AudioCaptureService()
    private let whisperService = WhisperService()
    private let outputManager = OutputManager()
    private let overlayWindow = OverlayWindow()
    private let downloadOverlay = DownloadOverlayWindow()
    let updaterController = UpdaterController()

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AppDelegate")

    private var modelLoadTask: Task<Void, Never>?
    private var isModelLoadInProgress = false
    private var modelLoadID = UUID()

    private enum DictationState {
        case idle
        case recording
        case transcribing
    }

    private var dictationState: DictationState = .idle

    /// Unique ID for the current dictation session.
    /// Changed on each startDictation/cancelDictation so that stale transcription
    /// tasks (from a previous session) detect the mismatch and skip UI updates.
    private var dictationID = UUID()

    private var transcriptionTask: Task<Void, Never>?

    private var modelState: WhisperService.State = .notReady

    private var downloadStatesByModelId: [String: ModelDownloadState] = [:]
    private var activeDownloadModelId: String?

    private enum NonDictationUIState {
        case ready
        case downloading(ModelDownloadState)
        case loadingModel
        case error
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        setupNotifications()

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        updaterController.checkForUpdatesOnLaunchIfNeeded()

        modelLoadTask = Task { [weak self] in
            guard let self else { return }
            await loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        modelLoadTask?.cancel()
        cancelDictation()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelChange),
            name: Constants.Notifications.modelDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelDownloadState(_:)),
            name: Constants.Notifications.modelDownloadStateDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyChange),
            name: Constants.Notifications.hotkeyDidChange,
            object: nil
        )
    }

    @objc private func handleHotkeyChange() {
        setupHotkey()
    }

    @objc private func handleModelChange() {
        modelLoadTask?.cancel()
        cancelDictation()
        modelLoadTask = Task { [weak self] in
            guard let self else { return }
            await whisperService.unloadModel()
            if Task.isCancelled { return }
            await loadModel()
        }
    }

    private func loadModel() async {
        guard !Task.isCancelled else { return }
        let currentLoadID = UUID()
        modelLoadID = currentLoadID
        isModelLoadInProgress = true
        defer {
            if modelLoadID == currentLoadID {
                isModelLoadInProgress = false
            }
        }

        whisperService.setStateCallback { [weak self] state in
            Task { @MainActor in
                self?.handleModelState(state)
            }
        }

        do {
            try await whisperService.ensureModelLoaded()
        } catch is CancellationError {
            return
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription)")
            modelState = .error(error.localizedDescription)
            syncNonDictationUI()
            showModelLoadError(error)
        }
    }

    private func showModelLoadError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Load Model"
        alert.informativeText = "The transcription model could not be loaded: \(error.localizedDescription)\n\nDictation is unavailable until a model loads successfully. Please check your internet connection and try restarting the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            modelLoadTask?.cancel()
            modelLoadTask = Task { [weak self] in
                guard let self else { return }
                await self.loadModel()
            }
        }
    }

    private func handleModelState(_ state: WhisperService.State) {
        modelState = state

        switch state {
        case .notReady, .loading, .ready:
            syncNonDictationUI()
        case .error(let message):
            logger.error("Model error: \(message)")
            syncNonDictationUI()
        }
    }

    private enum AppState {
        case downloading
        case ready
        case recording
        case transcribing
        case error
    }

    private func updateStatusIcon(state: AppState) {
        let iconName: String
        switch state {
        case .downloading:
            iconName = "arrow.down.circle"
        case .ready:
            iconName = "waveform"
        case .recording:
            iconName = "waveform.circle.fill"
        case .transcribing:
            iconName = "ellipsis.circle"
        case .error:
            iconName = "exclamationmark.triangle"
        }

        guard let button = statusItem?.button else {
            logger.error("Status item button unavailable when trying to update icon")
            return
        }

        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Jabber")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jabber")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 200)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView(updaterController: updaterController))
    }

    private func setupHotkey() {
        let keyCode = HotkeyManager.savedKeyCode()
        let modifiers = HotkeyManager.savedModifiers()
        hotkeyManager.register(keyCode: keyCode, modifiers: modifiers)

        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyDown()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyUp()
            }
        }

        hotkeyManager.onRegistrationFailure = { [weak self] status in
            Task { @MainActor in
                self?.logger.error("Hotkey registration failed with status: \(status)")
                NotificationService.shared.showError(
                    title: "Hotkey Registration Failed",
                    message: "Could not register the global hotkey (⌥ Space). It may be in use by another application.",
                    critical: false
                )
            }
        }
    }

    private func handleHotkeyDown() {
        guard whisperService.isReady else { return }

        switch dictationState {
        case .idle:
            startDictation()
        case .recording:
            break
        case .transcribing:
            cancelDictation()
            startDictation()
        }
    }

    private func handleHotkeyUp() {
        guard dictationState == .recording else { return }
        stopDictationAndTranscribe()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func startDictation() {
        guard whisperService.isReady else {
            // Model not ready yet, ignore
            return
        }

        dictationID = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        overlayWindow.show()
        downloadOverlay.hide()

        audioCapture.onAudioLevel = { [weak self] level in
            self?.overlayWindow.updateLevel(level)
        }

        audioCapture.onConversionError = { [weak self] error in
            Task { @MainActor in
                self?.logger.error("Audio conversion error: \(error.localizedDescription)")
                NotificationService.shared.showError(
                    title: "Audio Processing Error",
                    message: "Failed to process audio: \(error.localizedDescription)",
                    critical: false
                )
            }
        }

        do {
            try audioCapture.startCapture()
            dictationState = .recording
            updateStatusIcon(state: .recording)
        } catch {
            logger.error("Failed to start audio capture: \(error.localizedDescription)")
            dictationState = .idle
            overlayWindow.hide()
            updateStatusIcon(state: .error)
            NotificationService.shared.showError(
                title: "Audio Capture Failed",
                message: "Could not access the microphone. Please check your system permissions.",
                critical: false
            )
        }
    }

    private func stopDictationAndTranscribe() {
        audioCapture.stopCapture()
        dictationState = .transcribing
        updateStatusIcon(state: .transcribing)

        let samples = audioCapture.currentSamples()
        guard !samples.isEmpty else {
            finishDictation(dictationID: dictationID)
            return
        }

        overlayWindow.showProcessing()

        let currentID = dictationID
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await self.transcribeAndOutput(samples: samples, dictationID: currentID)
        }
    }

    private func transcribeAndOutput(samples: [Float], dictationID: UUID) async {
        do {
            try Task.checkCancellation()

            // Sync vocabulary prompt and language from settings
            let vocab = UserDefaults.standard.string(forKey: "vocabularyPrompt") ?? ""
            await whisperService.setVocabularyPrompt(vocab)

            let language = UserDefaults.standard.string(forKey: "selectedLanguage") ?? Constants.defaultLanguage
            await whisperService.setLanguage(language)

            try Task.checkCancellation()

            let text = try await whisperService.transcribe(samples: samples)

            try Task.checkCancellation()

            if !text.isEmpty {
                outputManager.output(text)
            } else {
                NotificationService.shared.showWarning(
                    title: "No Speech Detected",
                    message: "Could not detect any speech in the recording. Try speaking louder or closer to the microphone."
                )
            }
        } catch is CancellationError {
            // cancellation is ok
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            NotificationService.shared.showError(
                title: "Transcription Failed",
                message: "Could not transcribe audio: \(error.localizedDescription)",
                critical: false
            )
        }

        finishDictation(dictationID: dictationID)
    }

    private func finishDictation(dictationID: UUID) {
        guard self.dictationID == dictationID else { return }
        transcriptionTask = nil
        dictationState = .idle
        overlayWindow.hide()
        syncNonDictationUI()
    }

    private func cancelDictation() {
        dictationID = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        dictationState = .idle
        audioCapture.stopCapture()
        overlayWindow.hide()
        syncNonDictationUI()
    }

    @objc private func handleModelDownloadState(_ notification: Notification) {
        guard let state = notification.object as? ModelDownloadState else { return }

        updateDownloadTracking(with: state)
        syncNonDictationUI(forceLoading: shouldForceLoading(for: state))
    }

    private func updateDownloadTracking(with state: ModelDownloadState) {
        switch state.phase {
        case .started, .progress:
            downloadStatesByModelId[state.modelId] = state
            activeDownloadModelId = state.modelId
        case .finished, .failed:
            downloadStatesByModelId[state.modelId] = nil
            if activeDownloadModelId == state.modelId {
                activeDownloadModelId = downloadStatesByModelId.keys.first
            }
        }
    }

    private var selectedModelId: String? {
        UserDefaults.standard.string(forKey: "selectedModel")
    }

    private func shouldForceLoading(for state: ModelDownloadState) -> Bool {
        state.phase == .finished
            && isModelLoadInProgress
            && state.modelId == selectedModelId
    }

    private func currentDownloadForUI() -> ModelDownloadState? {
        if let selectedModelId,
           let state = downloadStatesByModelId[selectedModelId] {
            return state
        }
        if let activeDownloadModelId,
           let state = downloadStatesByModelId[activeDownloadModelId] {
            return state
        }
        return downloadStatesByModelId.values.first
    }

    private func syncNonDictationUI(forceLoading: Bool = false) {
        guard dictationState == .idle else {
            downloadOverlay.hide()
            return
        }

        applyNonDictationUI(resolveNonDictationUI(forceLoading: forceLoading))
    }

    private func resolveNonDictationUI(forceLoading: Bool) -> NonDictationUIState {
        switch (forceLoading, modelState, isModelLoadInProgress, currentDownloadForUI()) {
        case (_, .error, _, _):
            return .error
        case (true, _, _, _):
            return .loadingModel
        case (_, .loading, true, _):
            return .loadingModel
        case (_, _, _, let download?):
            return .downloading(download)
        case (_, .ready, _, _), (_, .notReady, _, _):
            return .ready
        case (_, .loading, _, _):
            return .loadingModel
        }
    }

    private func applyNonDictationUI(_ state: NonDictationUIState) {
        switch state {
        case .ready:
            downloadOverlay.hide()
            updateStatusIcon(state: .ready)
        case .downloading(let download):
            downloadOverlay.show()
            downloadOverlay.updateProgress(download.progress, status: download.status)
            updateStatusIcon(state: .downloading)
        case .loadingModel:
            downloadOverlay.show()
            downloadOverlay.updateProgress(0, status: "Loading model...", indeterminate: true)
            updateStatusIcon(state: .downloading)
        case .error:
            downloadOverlay.hide()
            updateStatusIcon(state: .error)
        }
    }
}
