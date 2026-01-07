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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        setupNotifications()

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        Task {
            await ModelManager.shared.ensureDefaultModelDownloaded()
            await loadModel()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModelChange),
            name: .modelDidChange,
            object: nil
        )
    }

    @objc private func handleModelChange() {
        Task {
            await whisperService.unloadModel()
            await loadModel()
        }
    }

    private func loadModel() async {
        whisperService.setStateCallback { [weak self] state in
            Task { @MainActor in
                self?.handleModelState(state)
            }
        }

        do {
            try await whisperService.ensureModelLoaded()
        } catch {
            logger.error("Failed to load model: \(error.localizedDescription)")
            updateStatusIcon(state: .error)
            downloadOverlay.hide()
            showModelLoadError(error)
        }
    }

    private func showModelLoadError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Load Model"
        alert.informativeText = "The transcription model could not be loaded: \(error.localizedDescription)\n\nPlease check your internet connection and try restarting the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task {
                await loadModel()
            }
        }
    }

    private func handleModelState(_ state: WhisperService.State) {
        switch state {
        case .notReady:
            break
        case .downloading(let progress, let status):
            downloadOverlay.show()
            downloadOverlay.updateProgress(progress, status: status)
        case .loading:
            downloadOverlay.updateProgress(1.0, status: "Loading model...")
        case .ready:
            downloadOverlay.hide()
            updateStatusIcon(state: .ready)
        case .error(let message):
            logger.error("Model error: \(message)")
            downloadOverlay.hide()
            updateStatusIcon(state: .error)
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
        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Jabber")
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
        // Default: Option + Space (0x31 = space, optionKey = 0x0800)
        hotkeyManager.register(keyCode: 0x31, modifiers: UInt32(Carbon.optionKey))

        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startDictation()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopDictationAndTranscribe()
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

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func startDictation() {
        guard whisperService.isReady else {
            // Model not ready yet, ignore
            return
        }

        overlayWindow.show()

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
            updateStatusIcon(state: .recording)
        } catch {
            logger.error("Failed to start audio capture: \(error.localizedDescription)")
            overlayWindow.hide()
            updateStatusIcon(state: .error)
            NotificationService.shared.showError(
                title: "Audio Capture Failed",
                message: "Could not access the microphone. Please check your system permissions.",
                critical: false
            )
        }
    }

    private func stopDictationAndTranscribe() async {
        audioCapture.stopCapture()
        updateStatusIcon(state: .transcribing)

        let samples = audioCapture.currentSamples()
        guard !samples.isEmpty else {
            overlayWindow.hide()
            updateStatusIcon(state: .ready)
            return
        }

        overlayWindow.showProcessing()

        // Sync vocabulary prompt from settings
        let vocab = UserDefaults.standard.string(forKey: "vocabularyPrompt") ?? ""
        await whisperService.setVocabularyPrompt(vocab)

        do {
            let text = try await whisperService.transcribe(samples: samples)
            if !text.isEmpty {
                outputManager.output(text)
            } else {
                NotificationService.shared.showWarning(
                    title: "No Speech Detected",
                    message: "Could not detect any speech in the recording. Try speaking louder or closer to the microphone."
                )
            }
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            NotificationService.shared.showError(
                title: "Transcription Failed",
                message: "Could not transcribe audio: \(error.localizedDescription)",
                critical: false
            )
        }

        overlayWindow.hide()
        updateStatusIcon(state: .ready)
    }
}
