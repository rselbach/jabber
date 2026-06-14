import AppKit
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private let hotkeyManager = HotkeyManager()
    private let audioCapture = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let outputManager = OutputManager()
    private let permissionService = PermissionService.shared
    private let overlayWindow = OverlayWindow()
    private let downloadOverlay = DownloadOverlayWindow()
    let updaterController = UpdaterController()

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AppDelegate")

    private var modelLoadTask: Task<Void, Never>?
    private var firstRunSetupTask: Task<Void, Never>?
    private var isModelLoadInProgress = false
    private var modelLoadID = UUID()

    private lazy var dictationCoordinator = DictationCoordinator(
        audioCapture: audioCapture,
        transcriptionService: transcriptionService,
        outputManager: outputManager
    )

    private var lastModelUnavailableNotice = CFAbsoluteTime(0)
    private var lastTranscriptionBusyNotice = CFAbsoluteTime(0)

    private var modelState: TranscriptionService.State = .notReady

    private var downloadStatesByModelId: [String: ModelDownloadState] = [:]
    private var activeDownloadModelId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        setupDictationCoordinator()
        setupNotifications()
        setupModelStateCallback()

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        updaterController.checkForUpdatesOnLaunchIfNeeded()

        modelLoadTask = Task { [weak self] in
            guard let self else { return }
            await loadModel()
        }
        scheduleFirstRunSetupPrompt()
    }

    func applicationWillTerminate(_ notification: Notification) {
        modelLoadTask?.cancel()
        firstRunSetupTask?.cancel()
        dictationCoordinator.cancel()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyCaptureBegin),
            name: Constants.Notifications.hotkeyCaptureDidBegin,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyCaptureEnd),
            name: Constants.Notifications.hotkeyCaptureDidEnd,
            object: nil
        )
    }

    @objc private func handleModelChange() {
        modelLoadTask?.cancel()
        dictationCoordinator.cancel()
        modelLoadTask = Task { [weak self] in
            guard let self else { return }
            await transcriptionService.unloadModel()
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

        do {
            try await transcriptionService.ensureModelLoaded()
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

    private func handleModelState(_ state: TranscriptionService.State) {
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
        popover?.contentSize = NSSize(width: 320, height: 420)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView(updaterController: updaterController))
    }

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyDown()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyUp()
            }
        }

        hotkeyManager.onRegistrationFailure = { [weak self] status in
            self?.logger.error("Hotkey registration failed with status: \(status)")
            let display = TypedSettings.hotkeyShortcut.displayString
            NotificationService.shared.showError(
                title: "Hotkey Registration Failed",
                message: "Could not register the global hotkey (\(display)). It may be in use by another application. OSStatus: \(status)",
                critical: false
            )
        }

        registerConfiguredHotkey()
    }

    private func setupDictationCoordinator() {
        dictationCoordinator.onStateChange = { [weak self] state in
            self?.handleDictationStateChange(state)
        }

        dictationCoordinator.onAudioLevel = { [weak self] level in
            self?.overlayWindow.updateLevel(level)
        }

        dictationCoordinator.onAudioConversionError = { [weak self] error in
            guard let self else { return }
            self.logger.error("Audio conversion error: \(error.localizedDescription)")
            NotificationService.shared.showError(
                title: "Audio Processing Error",
                message: "Failed to process audio: \(error.localizedDescription)",
                critical: false
            )
        }

        dictationCoordinator.onNoSpeechDetected = { [weak self] in
            self?.showNoSpeechDetectedWarning()
        }

        dictationCoordinator.onTranscriptionError = { [weak self] error in
            guard let self else { return }
            self.logger.error("Transcription failed: \(error.localizedDescription)")
            NotificationService.shared.showError(
                title: "Transcription Failed",
                message: "Could not transcribe audio: \(error.localizedDescription)",
                critical: false
            )
        }
    }

    private func setupModelStateCallback() {
        transcriptionService.setStateCallback { [weak self] state in
            Task { @MainActor in
                self?.handleModelState(state)
            }
        }
    }

    @objc private func handleHotkeyChange() {
        registerConfiguredHotkey()
    }

    @objc private func handleHotkeyCaptureBegin() {
        hotkeyManager.unregister()
    }

    @objc private func handleHotkeyCaptureEnd() {
        registerConfiguredHotkey()
    }

    private func registerConfiguredHotkey() {
        hotkeyManager.register(TypedSettings.hotkeyShortcut)
    }

    private func handleHotkeyDown() async {
        guard transcriptionService.isReady else {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastModelUnavailableNotice > 1.5 {
                lastModelUnavailableNotice = now
                NotificationService.shared.showWarning(
                    title: "Model Not Ready",
                    message: "Jabber is still preparing the speech model. Try again in a moment."
                )
                showSetupPopoverIfNeeded()
            }
            return
        }

        guard !dictationCoordinator.isTranscribing else {
            showTranscriptionBusyNotice()
            return
        }

        let hasMicrophonePermission = await permissionService.requestMicrophonePermission()
        guard hasMicrophonePermission else {
            NotificationService.shared.showPermissionWarning(
                title: "Microphone Permission Required",
                message: "Jabber needs microphone access to record speech.",
                section: .microphone
            )
            showSetupPopoverIfNeeded()
            return
        }

        guard ensureOutputPermissionReady() else { return }

        if dictationCoordinator.isRecording { return }

        guard dictationCoordinator.canStart else {
            showTranscriptionBusyNotice()
            return
        }

        _ = dictationCoordinator.start()
    }

    private func handleHotkeyUp() {
        dictationCoordinator.stop()
    }

    private func ensureOutputPermissionReady() -> Bool {
        guard outputManager.requiresAccessibilityPermission else { return true }
        guard !permissionService.hasAccessibilityPermission() else { return true }
        guard permissionService.requestAccessibilityPermission() else {
            NotificationService.shared.showPermissionWarning(
                title: "Accessibility Permission Required",
                message: "Grant accessibility permission before dictating in paste mode, or switch output to Copy to clipboard in Settings.",
                section: .accessibility
            )
            showSetupPopoverIfNeeded()
            return false
        }
        return true
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(relativeTo: button, activateApp: true)
        }
    }

    private func scheduleFirstRunSetupPrompt() {
        firstRunSetupTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch is CancellationError {
                return
            } catch {
                self?.logger.error("Failed while waiting to show first-run setup: \(error.localizedDescription)")
                return
            }

            self?.showFirstRunSetupIfNeeded()
        }
    }

    private func showFirstRunSetupIfNeeded() {
        guard !TypedSettings[BoolSetting.didShowFirstRunSetup] else { return }
        TypedSettings[BoolSetting.didShowFirstRunSetup] = true

        guard !currentSetupReadiness().isComplete else { return }
        showSetupPopover()
    }

    private func currentSetupReadiness() -> SetupReadiness {
        SetupReadinessResolver.resolve(
            hasMicrophonePermission: permissionService.hasMicrophonePermission(),
            hasAccessibilityPermission: permissionService.hasAccessibilityPermission(),
            requiresAccessibilityPermission: outputManager.requiresAccessibilityPermission,
            hasDownloadedModel: ModelManager.shared.hasAnyDownloadedModel,
            isDownloadingModel: ModelManager.shared.models.contains { $0.isDownloading }
        )
    }

    private func showSetupPopoverIfNeeded() {
        guard !currentSetupReadiness().isComplete else { return }
        showSetupPopover()
    }

    private func showSetupPopover() {
        guard let button = statusItem?.button else {
            logger.error("Status item button unavailable when trying to show setup popover")
            return
        }

        showPopover(relativeTo: button, activateApp: false)
    }

    private func showPopover(relativeTo button: NSStatusBarButton, activateApp: Bool) {
        guard let popover else {
            logger.error("Popover unavailable when trying to show setup guidance")
            return
        }
        guard !popover.isShown else { return }

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func handleDictationStateChange(_ state: DictationCoordinator.State) {
        switch state {
        case .idle:
            overlayWindow.hide()
            syncNonDictationUI()
        case .recording:
            downloadOverlay.hide()
            overlayWindow.show()
            updateStatusIcon(state: .recording)
        case .transcribing:
            overlayWindow.showProcessing()
            updateStatusIcon(state: .transcribing)
        }
    }

    private func showNoSpeechDetectedWarning() {
        NotificationService.shared.showWarning(
            title: "No Speech Detected",
            message: "Could not detect any speech in the recording. Try speaking louder or closer to the microphone."
        )
    }

    private func showTranscriptionBusyNotice() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastTranscriptionBusyNotice > 1.5 else { return }
        lastTranscriptionBusyNotice = now
        NotificationService.shared.showWarning(
            title: "Still Transcribing",
            message: "Jabber is finishing the previous dictation. Try again in a moment."
        )
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
        ModelManager.shared.selectedModelId()
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
        guard dictationCoordinator.isIdle else {
            downloadOverlay.hide()
            return
        }

        applyNonDictationUI(resolveNonDictationUI(forceLoading: forceLoading))
    }

    private func resolveNonDictationUI(forceLoading: Bool) -> NonDictationUIState {
        NonDictationUIResolver.resolve(
            forceLoading: forceLoading,
            modelState: modelState,
            downloadState: currentDownloadForUI()
        )
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
        case .loadingModel(let status, let progress):
            downloadOverlay.show()
            if let progress {
                downloadOverlay.updateProgress(progress, status: status)
            } else {
                downloadOverlay.updateProgress(0, status: status, indeterminate: true)
            }
            updateStatusIcon(state: .downloading)
        case .error:
            downloadOverlay.hide()
            updateStatusIcon(state: .error)
        }
    }
}
