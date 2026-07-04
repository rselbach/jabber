import AppKit
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var onboardingWindow: NSWindow?
    private var onboardingCoordinator: OnboardingCoordinator?
    private var mainWindow: NSWindow?
    private var modelMigrationNoticeWindow: NSWindow?

    private let hotkeyManager = HotkeyManager()
    private let audioCapture = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let typingService = TypingService()
    private let permissionService = PermissionService.shared
    private let overlayWindow = OverlayWindow()
    private let downloadOverlay = DownloadOverlayWindow()
    let updaterController = UpdaterController()

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "AppDelegate")

    private var modelLoadTask: Task<Void, Never>?
    private var firstRunSetupTask: Task<Void, Never>?
    private var modelMigrationNoticeTask: Task<Void, Never>?
    private var isModelLoadInProgress = false
    private var modelLoadID = UUID()

    private lazy var dictationCoordinator = DictationCoordinator(
        audioCapture: audioCapture,
        transcriptionService: transcriptionService,
        typingService: typingService
    )

    private var lastModelUnavailableNotice = CFAbsoluteTime(0)
    private var lastTranscriptionBusyNotice = CFAbsoluteTime(0)
    private var lastPostProcessingFailureNotice = CFAbsoluteTime(0)
    private var didPromptAccessibility = false
    private static let automaticHotkeyHoldThreshold: TimeInterval = 0.4

    // Hotkey press tracking: a press that awaits microphone permission can
    // have its key released before `start()` runs, leaving a "stuck" recording.
    // `currentHotkeyPressID` identifies each attempted press; if a release
    // arrives while a press is still awaiting start, `abortedHotkeyPressIDs`
    // records it so the press aborts instead of starting after release.
    private var currentHotkeyPressID = 0
    private var pendingHotkeyStartID: Int?
    private var abortedHotkeyPressIDs: Set<Int> = []
    private var activeHotkeyPressMode: HotkeyActivationMode?
    private var automaticHotkeyPressStartedAt: CFAbsoluteTime?
    private var automaticHotkeyPressStartedRecording = false

    private var modelState: TranscriptionService.State = .notReady

    private var currentTargetProcessID: pid_t?

    private var downloadStatesByModelId: [String: ModelDownloadState] = [:]
    private var activeDownloadModelId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Normalize stale stored settings before any SwiftUI view mounts, so
        // `@AppStorage` reads never observe a pre-migration value and the
        // SettingsStore getters can stay pure (no writes during view updates).
        TypedSettings.migrateStoredValues()
        setupMenuBar()
        setupHotkey()
        setupDictationCoordinator()
        setupNotifications()
        setupModelStateCallback()

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        updaterController.checkForUpdatesOnLaunchIfNeeded()

        // Resolve the model-migration notice synchronously: a user whose
        // selected model was removed in an update should NOT have the
        // replacement auto-downloaded out from under the prompt that's about
        // to ask them what to do. Skip the load task when a notice is
        // pending; presentation is still delayed for politeness.
        let willShowOnboarding = shouldShowAutomaticOnboarding()
        let pendingNotice = pendingModelMigrationNotice()

        // Onboarding owns model selection for new users; let it drive any
        // download via its own model-download step. Starting the load task
        // here would pull a multi-GB default model the user may not pick.
        if !willShowOnboarding, pendingNotice == nil {
            startModelLoadingTask()
        }
        scheduleUIReadyFallbackIfNeeded()
        scheduleFirstRunSetupPrompt()
        if let pendingNotice {
            scheduleModelMigrationNoticePresentation(pendingNotice)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        modelLoadTask?.cancel()
        firstRunSetupTask?.cancel()
        modelMigrationNoticeTask?.cancel()
        onboardingCoordinator?.stop()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOnboardingRequest),
            name: Constants.Notifications.onboardingDidRequest,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMainWindowRequest),
            name: Constants.Notifications.mainWindowDidRequest,
            object: nil
        )
    }

    func markUIReadyFromView() {
        AppReadinessGate.shared.markUIReady()
    }

    private func scheduleUIReadyFallbackIfNeeded() {
        guard !shouldShowAutomaticOnboarding() else { return }

        Task { @MainActor in
            await Task.yield()
            AppReadinessGate.shared.markUIReady()
        }
    }

    private func startModelLoadingTask() {
        modelLoadTask = Task { [weak self] in
            guard let self else { return }
            await loadModel()
        }
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
        await AppReadinessGate.shared.waitForUIReady()
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
            startModelLoadingTask()
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
        }

        let menu = buildMenu()
        statusItem?.menu = menu
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Jabber", action: #selector(openJabber), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        let vocabularyItem = NSMenuItem(title: "Vocabulary", action: #selector(openVocabulary), keyEquivalent: "")
        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit Jabber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in [openItem, settingsItem, vocabularyItem, updatesItem] {
            item.target = self
        }
        // quitItem has no target → routes through the responder chain to NSApp.terminate.

        menu.items = [openItem, settingsItem, vocabularyItem, .separator(), updatesItem, .separator(), quitItem]
        return menu
    }

    @objc private func openJabber() {
        showMainWindow(initialSection: .gettingStarted)
    }

    @objc private func openSettings() {
        showMainWindow(initialSection: .general)
    }

    @objc private func openVocabulary() {
        showMainWindow(initialSection: .vocabulary)
        // `showMainWindow` honors `initialSection` only when creating the
        // window; when it is already open the selection is driven via this
        // notification so the Vocabulary item always lands on the right page.
        NotificationCenter.default.post(
            name: Constants.Notifications.mainWindowSectionDidRequest,
            object: MainWindowView.Section.vocabulary
        )
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates()
    }

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                await self?.handleHotkeyDownEvent()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyUpEvent()
            }
        }

        hotkeyManager.onRegistrationFailure = { [weak self] status in
            self?.logger.error("Hotkey registration failed with status: \(status)")
            let shortcut = TypedSettings.hotkeyShortcut
            let display = shortcut.displayString
            let message: String
            if shortcut.isModifierOnly {
                message = "Could not register \(display) as a global hotkey. Lone modifier keys require Accessibility permission in System Settings. OSStatus: \(status)"
            } else {
                message = "Could not register the global hotkey (\(display)). It may be in use by another application. OSStatus: \(status)"
            }
            NotificationService.shared.showError(
                title: "Hotkey Registration Failed",
                message: message,
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

        dictationCoordinator.onPartialTranscription = { [weak self] text in
            self?.overlayWindow.updatePartialTranscription(text)
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

        dictationCoordinator.onRefining = { [weak self] in
            self?.overlayWindow.showRefining()
        }

        dictationCoordinator.onPostProcessingError = { [weak self] error in
            guard let self else { return }
            self.logger.error("Post-processing failed: \(error.localizedDescription)")
            self.showPostProcessingFailureNotice(error)
        }

        dictationCoordinator.onPostProcessingFallback = { [weak self] in
            guard let self else { return }
            self.logger.notice("Post-processing fell back to raw transcript after guardrail rejection")
            self.overlayWindow.showFallbackNotice("Post-processing looked wrong — used raw transcript")
        }
    }

    private func setupModelStateCallback() {
        // `handle` is a @MainActor closure so the weak-self read happens on the
        // main actor (clean under StrictConcurrency); it is @Sendable so it can
        // be captured by the @Sendable state callback below.
        let handle: @Sendable @MainActor (TranscriptionService.State) -> Void = { [weak self] state in
            self?.handleModelState(state)
        }
        transcriptionService.setStateCallback { state in
            // Serialize delivery over the FIFO main queue. A fresh unstructured
            // `Task { @MainActor }` per state change has no ordering guarantee,
            // so a rapid `.loading` -> `.ready` pair could apply reversed and
            // leave a stale status icon/overlay. The main dispatch queue is
            // serial, so submissions run in order; `assumeIsolated` runs the
            // `@MainActor` body synchronously without re-queue.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handle(state)
                }
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

    private var hasActiveOrPendingRecording: Bool {
        dictationCoordinator.isRecording || pendingHotkeyStartID != nil
    }

    private func handleHotkeyDownEvent() async {
        guard activeHotkeyPressMode == nil else { return }

        let mode = TypedSettings.hotkeyActivationMode
        activeHotkeyPressMode = mode

        switch mode {
        case .hold:
            await startDictationFromHotkey()
        case .toggle:
            if hasActiveOrPendingRecording {
                stopOrAbortDictationFromHotkey()
            } else {
                await startDictationFromHotkey()
            }
        case .automatic:
            automaticHotkeyPressStartedAt = CFAbsoluteTimeGetCurrent()
            if hasActiveOrPendingRecording {
                automaticHotkeyPressStartedRecording = false
                stopOrAbortDictationFromHotkey()
            } else {
                automaticHotkeyPressStartedRecording = true
                await startDictationFromHotkey()
            }
        }
    }

    private func handleHotkeyUpEvent() {
        let mode = activeHotkeyPressMode ?? TypedSettings.hotkeyActivationMode
        activeHotkeyPressMode = nil

        switch mode {
        case .hold:
            stopOrAbortDictationFromHotkey()
        case .toggle:
            break
        case .automatic:
            defer {
                automaticHotkeyPressStartedAt = nil
                automaticHotkeyPressStartedRecording = false
            }

            guard automaticHotkeyPressStartedRecording,
                  let startedAt = automaticHotkeyPressStartedAt else {
                return
            }

            let heldDuration = CFAbsoluteTimeGetCurrent() - startedAt
            if heldDuration >= Self.automaticHotkeyHoldThreshold {
                stopOrAbortDictationFromHotkey()
            }
        }
    }

    private func startDictationFromHotkey() async {
        currentHotkeyPressID += 1
        let pressID = currentHotkeyPressID
        pendingHotkeyStartID = pressID
        defer {
            if pendingHotkeyStartID == pressID {
                pendingHotkeyStartID = nil
            }
            abortedHotkeyPressIDs.remove(pressID)
        }

        guard transcriptionService.isReady else {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastModelUnavailableNotice > 1.5 {
                lastModelUnavailableNotice = now
                NotificationService.shared.showWarning(
                    title: "Model Not Ready",
                    message: "Jabber is still preparing the speech model. Try again in a moment."
                )
                showSetupGuidanceIfNeeded()
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
            showSetupGuidanceIfNeeded()
            return
        }

        // If the key was released while we were awaiting permission, treat this
        // press as aborted rather than starting a recording after release.
        if abortedHotkeyPressIDs.remove(pressID) != nil {
            return
        }

        guard ensureOutputPermissionReady() else { return }

        if dictationCoordinator.isRecording { return }

        guard dictationCoordinator.canStart else {
            showTranscriptionBusyNotice()
            return
        }

        let targetProcessID = TypingService.captureFocusedProcessID()
        currentTargetProcessID = targetProcessID
        _ = dictationCoordinator.start(targetProcessID: targetProcessID)
    }

    private func stopOrAbortDictationFromHotkey() {
        if dictationCoordinator.isRecording {
            dictationCoordinator.stop()
        } else {
            // Release arrived before recording began (e.g. during the permission
            // await). Mark the in-flight press aborted so it does not start.
            abortedHotkeyPressIDs.insert(pendingHotkeyStartID ?? currentHotkeyPressID)
        }
    }

    private func ensureOutputPermissionReady() -> Bool {
        guard typingService.requiresAccessibilityPermission else { return true }
        guard !permissionService.hasAccessibilityPermission() else { return true }

        showAccessibilityPermissionWarning()
        return false
    }

    private func showAccessibilityPermissionWarning() {
        NotificationService.shared.showPermissionWarning(
            title: "Accessibility Permission Required",
            message: "Grant accessibility permission before dictating into the active app, or switch output to Copy to clipboard in Settings.",
            section: .accessibility
        )
        showSetupGuidanceIfNeeded()

        guard !didPromptAccessibility else { return }
        didPromptAccessibility = true
        _ = permissionService.requestAccessibilityPermission()
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
        showOnboardingWindow(userInitiated: false)
    }

    @objc private func handleOnboardingRequest() {
        TypedSettings[.onboardingCompleted] = false
        showOnboardingWindow(userInitiated: true)
    }

    private func shouldShowAutomaticOnboarding() -> Bool {
        guard !TypedSettings[.onboardingCompleted] else { return false }
        guard !TypedSettings[.didShowFirstRunSetup] else { return false }
        return true
    }

    private func showOnboardingWindow(userInitiated: Bool) {
        if !userInitiated {
            guard shouldShowAutomaticOnboarding() else { return }
        }

        if let onboardingWindow {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.setActivationPolicy(.regular)

        let coordinator = OnboardingCoordinator()
        let rootView = OnboardingView(
            coordinator: coordinator,
            onComplete: { [weak self] in
                self?.completeOnboarding()
            },
            onAppearAction: { [weak self] in
                self?.markUIReadyFromView()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Jabber"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.identifier = NSUserInterfaceItemIdentifier("com.rselbach.jabber.onboarding")
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        onboardingCoordinator = coordinator
        onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func completeOnboarding() {
        TypedSettings[.onboardingCompleted] = true
        TypedSettings[.didShowFirstRunSetup] = true
        // windowWillClose refreshes the activation policy.
        onboardingWindow?.close()
        // Now that onboarding has settled the user's model choice, kick off
        // the load. It was intentionally skipped at launch (see
        // applicationDidFinishLaunching) so the default model wouldn't
        // auto-download during onboarding.
        startModelLoadingTask()
    }

    @objc private func handleMainWindowRequest() {
        showMainWindow()
    }

    // MARK: - Model Migration Notice

    /// After an update, a user may be sitting on a selected model id that no
    /// longer exists. `ModelManager` silently rewrites it on launch; this
    /// surfaces the change so they can download the replacement (or pick
    /// another) instead of discovering it mid-dictation. Called synchronously
    /// at launch so the load task can be skipped when a prompt is pending.
    private func pendingModelMigrationNotice() -> ModelMigrationNotice? {
        // Onboarding owns the new-user / pre-onboarding upgrade flow; don't
        // compete with it.
        guard !shouldShowAutomaticOnboarding() else { return nil }
        guard let migration = ModelManager.shared.lastMigration else { return nil }

        return ModelMigrationNoticeResolver.resolve(
            migration: migration,
            newModelDownloaded: ModelManager.shared.downloadedModels.contains { $0.id == migration.to },
            newModelIsBuiltIn: AppMode.modelDefinition(for: migration.to)?.isBuiltIn ?? false,
            lastShownKey: TypedSettings[.lastModelMigrationNoticeKey]
        )
    }

    private func scheduleModelMigrationNoticePresentation(_ notice: ModelMigrationNotice) {
        modelMigrationNoticeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch is CancellationError {
                return
            } catch {
                self?.logger.error("Failed while waiting to present model migration: \(error.localizedDescription)")
                return
            }
            self?.presentModelMigrationNotice(notice)
        }
    }

    private func presentModelMigrationNotice(_ notice: ModelMigrationNotice) {
        guard onboardingWindow == nil, modelMigrationNoticeWindow == nil else { return }
        showModelMigrationNotice(notice)
    }

    private func showModelMigrationNotice(_ notice: ModelMigrationNotice) {
        NSApp.setActivationPolicy(.regular)

        let newModelName = AppMode.modelDefinition(for: notice.migration.to)?.name ?? notice.migration.to
        let rootView = ModelMigrationNoticeView(
            newModelName: newModelName,
            onDownload: { [weak self] in
                TypedSettings[.lastModelMigrationNoticeKey] = notice.noticeKey
                ModelManager.shared.startDownload(notice.migration.to)
                self?.closeModelMigrationNotice()
            },
            onChooseAnother: { [weak self] in
                TypedSettings[.lastModelMigrationNoticeKey] = notice.noticeKey
                // Open the main window first so the activation policy stays
                // regular; closing the notice then drops back only if the
                // main window is also closed.
                self?.showMainWindow(initialSection: .speech)
                self?.closeModelMigrationNotice()
            },
            onNotNow: { [weak self] in
                TypedSettings[.lastModelMigrationNoticeKey] = notice.noticeKey
                self?.closeModelMigrationNotice()
            }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Jabber Was Updated"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.identifier = NSUserInterfaceItemIdentifier("com.rselbach.jabber.model-migration-notice")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        modelMigrationNoticeWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeModelMigrationNotice() {
        // windowWillClose clears the property and refreshes activation policy.
        modelMigrationNoticeWindow?.close()
    }

    /// Shows the main app window (sidebar navigation with all configuration
    /// pages). While it is open the app behaves like a regular application:
    /// dock icon, Cmd-Tab entry, main menu. `initialSection` is honored only
    /// when the window is first created; if it is already open the request
    /// just brings it forward.
    private func showMainWindow(initialSection: MainWindowView.Section = .gettingStarted) {
        NSApp.setActivationPolicy(.regular)

        if let mainWindow {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: MainWindowView(
            updaterController: updaterController,
            initialSelection: initialSection,
            onAppearAction: { [weak self] in
                self?.markUIReadyFromView()
            }
        ))
        // Let SwiftUI drive the window toolbar and title so the
        // NavigationSplitView sidebar gets the standard unified look.
        hosting.sceneBridgingOptions = [.toolbars, .title]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = "Jabber"
        window.identifier = NSUserInterfaceItemIdentifier("com.rselbach.jabber.main")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 880, height: 620))
        if !window.setFrameUsingName(Self.mainWindowFrameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.mainWindowFrameName)

        mainWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static let mainWindowFrameName = "com.rselbach.jabber.main"

    /// Drops back to accessory mode (menu bar only) once no user-facing
    /// window remains visible. `closingWindow` is excluded because
    /// `windowWillClose` fires while the window still reports visible.
    private func refreshActivationPolicy(closing closingWindow: NSWindow? = nil) {
        let hasVisibleUserWindow = [mainWindow, onboardingWindow, modelMigrationNoticeWindow]
            .compactMap { $0 }
            .contains { $0 !== closingWindow && $0.isVisible }
        NSApp.setActivationPolicy(hasVisibleUserWindow ? .regular : .accessory)
    }

    private func currentSetupReadiness() -> SetupReadiness {
        SetupReadinessResolver.resolve(
            hasMicrophonePermission: permissionService.hasMicrophonePermission(),
            hasAccessibilityPermission: permissionService.hasAccessibilityPermission(),
            requiresAccessibilityPermission: typingService.requiresAccessibilityPermission,
            hasDownloadedModel: ModelManager.shared.hasAnyDownloadedModel,
            isDownloadingModel: ModelManager.shared.models.contains { $0.isDownloading }
        )
    }

    private func showSetupGuidanceIfNeeded() {
        if shouldShowAutomaticOnboarding() {
            showOnboardingWindow(userInitiated: false)
            return
        }

        guard !currentSetupReadiness().isComplete else { return }
        showMainWindow(initialSection: .gettingStarted)
    }

    private func handleDictationStateChange(_ state: DictationCoordinator.State) {
        switch state {
        case .idle:
            overlayWindow.hide()
            overlayWindow.setTargetAppIcon(nil)
            currentTargetProcessID = nil
            syncNonDictationUI()
        case .recording:
            downloadOverlay.hide()
            overlayWindow.show()
            overlayWindow.setTargetAppIcon(
                TypingService.appIcon(forTargetProcessID: currentTargetProcessID)
            )
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

    /// Non-blocking notice that transcript refinement failed and the raw
    /// transcript was typed instead. Rate-limited so a flaky provider does not
    /// spam a notification on every dictation. Only true provider failures
    /// reach this path; guardrail rejections are surfaced non-disruptively via
    /// `overlayWindow.showFallbackNotice` instead. The message names the
    /// currently selected provider so it never blames Apple Intelligence when
    /// OpenRouter is the one that failed.
    private func showPostProcessingFailureNotice(_ error: Error) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPostProcessingFailureNotice > 1.5 else { return }
        lastPostProcessingFailureNotice = now

        let providerName = TypedSettings.postProcessingProviderKind.displayName
        NotificationService.shared.showWarning(
            title: "Couldn't Refine Transcript",
            message: "\(providerName) cleanup failed (\(error.localizedDescription)). Typed the raw transcript instead."
        )
    }

    @objc private func handleModelDownloadState(_ notification: Notification) {
        guard let state = notification.object as? ModelDownloadState else { return }

        updateDownloadTracking(with: state)

        // When the selected model finishes downloading, ensure a load starts.
        // This covers the migration-notice "Download" path, the notice's
        // "Choose Another" path (downloading the already-selected model is a
        // no-op via selectModel, so modelDidChange never fires), and the plain
        // Speech page "Download" button. Without this the freshly-downloaded
        // model sits unloaded until app restart.
        let isSelectedModelFinished = state.phase == .finished
            && state.modelId == selectedModelId

        if isSelectedModelFinished, !isModelLoadInProgress {
            startModelLoadingTask()
        }

        syncNonDictationUI(forceLoading: isSelectedModelFinished)
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
            downloadState: currentDownloadForUI(),
            isLoadInProgress: isModelLoadInProgress
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            onboardingCoordinator?.stop()
            onboardingCoordinator = nil
            onboardingWindow = nil
        } else if window === modelMigrationNoticeWindow {
            modelMigrationNoticeWindow = nil
        } else if window !== mainWindow {
            return
        }
        // The main window instance is kept so sidebar selection and view
        // state survive re-opening.

        refreshActivationPolicy(closing: window)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // AppKit re-validates each item when the menu opens (auto-enabling is
        // on by default). Without this, a target responding to `checkForUpdates`
        // is always enabled, clobbering `UpdaterController.canCheckForUpdates`.
        // Validating by action (not title) avoids the typographic-ellipsis
        // landmine of `menu.item(withTitle:)`.
        if item.action == #selector(checkForUpdates) {
            return updaterController.canCheckForUpdates
        }
        return true
    }
}
