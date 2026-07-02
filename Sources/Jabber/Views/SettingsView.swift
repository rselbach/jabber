import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updaterController: UpdaterController
    let onAppearAction: () -> Void

    @AppStorage(AppSettingKey.selectedModel) private var selectedModel = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
    @AppStorage(AppSettingKey.outputMode) private var outputMode = TypingService.OutputMode.directTyping.rawValue
    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @AppStorage(AppSettingKey.hotkeyActivationMode) private var hotkeyActivationMode = HotkeyActivationMode.defaultMode.rawValue
    @AppStorage(AppSettingKey.pauseMediaDuringRecording) private var pauseMediaDuringRecording = false
    @AppStorage(AppSettingKey.saveHistoryEnabled) private var saveHistoryEnabled = false
    @AppStorage(AppSettingKey.vocabularyPrompt) private var vocabularyPrompt = ""
    @AppStorage(AppSettingKey.postProcessingEnabled) private var postProcessingEnabled = false
    @AppStorage(AppSettingKey.selectedLanguage) private var selectedLanguage = Constants.defaultLanguage
    @AppStorage(AppSettingKey.onboardingCompleted) private var onboardingCompleted = false

    @State private var modelManager = ModelManager.shared
    @State private var permissionRefreshTick = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pendingDeleteModelId: String?
    @State private var pendingDeleteModelName: String?
    @State private var historyEntries: [DictationHistoryEntry] = []

    @State private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tag("general")
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            modelsTab
                .tag("models")
                .tabItem {
                    Label("Models", systemImage: "cube.box")
                }

            vocabularyTab
                .tag("vocabulary")
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }

            historyTab
                .tag("history")
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            aboutTab
                .tag("about")
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            onAppearAction()
            outputMode = TypingService.migratedOutputModeRawValue(outputMode)
            hotkeyActivationMode = selectedHotkeyActivationMode.rawValue
            permissionRefreshTick.toggle()
            _ = modelManager.migrateSelectedModelIfNeeded()
            modelManager.refreshModels()
            refreshHistoryEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshTick.toggle()
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.modelDownloadStateDidChange)) { notification in
            guard let state = notification.object as? ModelDownloadState else { return }
            guard state.phase == .failed, !state.isCancelled else { return }

            let modelName = modelManager.models.first { $0.id == state.modelId }?.name ?? state.modelId
            let details = state.errorDescription ?? state.status
            presentError("Failed to download \(modelName): \(details)")
        }
        .alert("Delete model", isPresented: Binding(
            get: { pendingDeleteModelId != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteModelId = nil
                    pendingDeleteModelName = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let modelId = pendingDeleteModelId,
                      let modelName = pendingDeleteModelName else {
                    pendingDeleteModelId = nil
                    return
                }
                do {
                    try modelManager.deleteModel(modelId)
                } catch {
                    presentError("Failed to delete \(modelName): \(error.localizedDescription)")
                }
                pendingDeleteModelId = nil
                pendingDeleteModelName = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModelId = nil
                pendingDeleteModelName = nil
            }
        } message: {
            Text("Delete \(pendingDeleteModelName ?? "")? This action removes local model files and cannot be undone.")
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private var setupReadiness: SetupReadiness {
        _ = permissionRefreshTick
        return SetupReadinessResolver.resolve(
            hasMicrophonePermission: PermissionService.shared.hasMicrophonePermission(),
            hasAccessibilityPermission: PermissionService.shared.hasAccessibilityPermission(),
            requiresAccessibilityPermission: selectedOutputMode.requiresAccessibilityPermission,
            hasDownloadedModel: modelManager.hasAnyDownloadedModel,
            isDownloadingModel: modelManager.models.contains { $0.isDownloading }
        )
    }

    private var selectedOutputMode: TypingService.OutputMode {
        TypingService.OutputMode(rawValue: TypingService.migratedOutputModeRawValue(outputMode)) ?? .directTyping
    }

    private var hotkeyShortcut: HotkeyShortcut {
        HotkeyShortcut(
            keyCode: UInt32(max(0, hotkeyKeyCode)),
            modifiers: UInt32(max(0, hotkeyModifiers))
        )
    }

    private var hotkeyDisplay: String {
        hotkeyShortcut.displayString
    }

    private var selectedHotkeyActivationMode: HotkeyActivationMode {
        HotkeyActivationMode(rawValue: hotkeyActivationMode) ?? .defaultMode
    }

    private var generalTab: some View {
        Form {
            setupSection

            Section {
                Picker("After transcription", selection: $outputMode) {
                    Text("Copy to clipboard").tag(TypingService.OutputMode.clipboard.rawValue)
                    Text("Type into active app").tag(TypingService.OutputMode.directTyping.rawValue)
                }
                .pickerStyle(.radioGroup)

                if selectedOutputMode == .directTyping {
                    Button("Open Accessibility Settings") {
                        PermissionService.shared.openPrivacySettings(for: .accessibility)
                    }
                    .buttonStyle(.borderless)

                    let isAccessibilityTrusted = PermissionService.shared.hasAccessibilityPermission()
                    if !isAccessibilityTrusted {
                        Text("Accessibility permission is currently disabled. Open Settings to enable it.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Output will be copied to the clipboard only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Output")
            }

            Section {
                Toggle("Pause media while recording", isOn: $pauseMediaDuringRecording)

                Text("When enabled, Jabber pauses current media playback when dictation starts and resumes only if Jabber paused it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Media")
            }

            Section {
                HStack {
                    Text("Press to talk:")
                    Spacer()
                    Text(hotkeyDisplay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                HotkeyRecorderView(
                    shortcut: hotkeyShortcut,
                    onShortcutChange: applyHotkeyShortcut
                )

                Picker("Activation", selection: $hotkeyActivationMode) {
                    ForEach(HotkeyActivationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .onChange(of: hotkeyActivationMode) { _, newValue in
                    applyHotkeyActivationModeRawValue(newValue)
                }

                Text(selectedHotkeyActivationMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset to ⌥ Space") {
                    applyHotkeyShortcut(.defaultShortcut)
                }
                .buttonStyle(.borderless)
                .disabled(hotkeyShortcut == .defaultShortcut)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Shortcuts must include Command, Control, or Option — or use a single modifier key like Right Option on its own — so Jabber does not steal every innocent keystroke like a gremlin.")
            }

            Section {
                LanguagePicker(selectedLanguage: $selectedLanguage)

                Text("Select a specific language or use auto-detect to identify it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Language")
            }

            Section {
                Toggle("Refine transcripts with Apple Intelligence", isOn: $postProcessingEnabled)

                Text("When enabled, Jabber asks the on-device Apple Intelligence model to clean up the final transcript — fixing punctuation, removing filler words and self-corrections — before typing it. Requires an Apple Intelligence-capable Mac with Apple Intelligence turned on. Falls back to the raw transcript if unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Apple Intelligence")
            }

            Section {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { updaterController.automaticallyChecksForUpdates },
                        set: { enabled in
                            updaterController.setAutomaticallyChecksForUpdates(enabled)
                        }
                    )
                )
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    private var setupSection: some View {
        Section {
            SetupChecklistView(
                readiness: setupReadiness,
                onRequestMicrophone: requestMicrophoneAccess,
                onOpenAccessibilitySettings: openAccessibilitySettings,
                onDownloadBaseModel: downloadBaseModel
            )

            Button("Run setup again") {
                runOnboardingAgain()
            }
        } header: {
            Text("Setup")
        } footer: {
            Text("Jabber needs these before dictation feels boringly reliable.")
        }
    }

    private func requestMicrophoneAccess() {
        Task { @MainActor in
            let granted = await PermissionService.shared.requestMicrophonePermission()
            if !granted {
                PermissionService.shared.openPrivacySettings(for: .microphone)
            }
            permissionRefreshTick.toggle()
        }
    }

    private func openAccessibilitySettings() {
        PermissionService.shared.openPrivacySettings(for: .accessibility)
        permissionRefreshTick.toggle()
    }

    private func downloadBaseModel() {
        let modelId = AppMode.modelDefinition(for: selectedModel)?.isBuiltIn == false
            ? selectedModel
            : LanguageModelCatalog.recommendedModelId(for: selectedLanguage)
        if !modelManager.startDownload(modelId) {
            modelManager.refreshModels()
        }
    }

    private func runOnboardingAgain() {
        onboardingCompleted = false
        NotificationCenter.default.post(
            name: Constants.Notifications.onboardingDidRequest,
            object: nil
        )
    }

    private func applyHotkeyShortcut(_ shortcut: HotkeyShortcut) {
        hotkeyKeyCode = Int(shortcut.keyCode)
        hotkeyModifiers = Int(shortcut.modifiers)
        NotificationCenter.default.post(
            name: Constants.Notifications.hotkeyDidChange,
            object: shortcut
        )
    }

    private func applyHotkeyActivationModeRawValue(_ rawValue: String) {
        let mode = HotkeyActivationMode(rawValue: rawValue) ?? .defaultMode
        if hotkeyActivationMode != mode.rawValue {
            hotkeyActivationMode = mode.rawValue
        }
        NotificationCenter.default.post(
            name: Constants.Notifications.hotkeyDidChange,
            object: mode
        )
    }

    private var modelsTab: some View {
        Form {
            Section {
                ForEach(modelManager.models) { model in
                    ModelRow(
                        model: model,
                        isSelected: selectedModel == model.id,
                        onSelect: {
                            guard model.isDownloaded else { return }
                            if modelManager.selectModel(model.id) {
                                selectedModel = model.id
                            }
                        },
                        onDownload: {
                            _ = modelManager.startDownload(model.id)
                        },
                        onDelete: {
                            pendingDeleteModelId = model.id
                            pendingDeleteModelName = model.name
                        },
                        onCancelDownload: {
                            modelManager.cancelDownload(model.id)
                        }
                    )
                }

                Text("Larger models are more accurate but slower and use more memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Models")
            }
        }
        .formStyle(.grouped)
    }

    private var vocabularyTab: some View {
        Form {
            Section {
                TextEditor(text: $vocabularyPrompt)
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .font(.body.monospaced())

                Text("Add names, technical terms, or jargon to improve recognition. One per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Custom Vocabulary")
            }
        }
        .formStyle(.grouped)
    }

    private var historyTab: some View {
        Form {
            Section {
                Toggle("Save dictation history", isOn: $saveHistoryEnabled)

                Text("When enabled, Jabber saves recent audio and transcripts locally for debugging. Retention is capped at 50 sessions or 500MB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh") {
                        refreshHistoryEntries()
                    }
                    .buttonStyle(.borderless)

                    Button("Reveal History Folder") {
                        revealHistoryFolder()
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Local Debug History")
            }

            Section {
                if historyEntries.isEmpty {
                    Text(saveHistoryEnabled ? "No saved dictations yet." : "History is disabled.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyEntries) { entry in
                        HistoryEntryRow(entry: entry) {
                            revealHistoryEntry(entry)
                        }
                    }
                }
            } header: {
                Text("Recent Sessions")
            }
        }
        .formStyle(.grouped)
    }

    private func refreshHistoryEntries() {
        Task { @MainActor in
            historyEntries = await DictationHistoryStore.shared.entries()
        }
    }

    private func revealHistoryFolder() {
        Task { @MainActor in
            let historyDirectoryURL = DictationHistoryStore.shared.historyDirectoryURL()
            do {
                try FileManager.default.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([historyDirectoryURL])
            } catch {
                presentError("Failed to open history folder: \(error.localizedDescription)")
            }
        }
    }

    private func revealHistoryEntry(_ entry: DictationHistoryEntry) {
        Task { @MainActor in
            let audioURL = DictationHistoryStore.shared.audioURL(for: entry)
            NSWorkspace.shared.activateFileViewerSelecting([audioURL])
        }
    }

    private var aboutTab: some View {
        Form {
            Section {
                Text("Jabber")
                    .font(.headline)
                Text("Local speech-to-text for macOS. All processing happens on-device.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }

            Section {
                ForEach(AppMode.modelDefinitions) { def in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(def.name)
                            .font(.body)
                        Text(def.attribution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(def.license, destination: URL(string: def.licenseUrl)!)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Models")
            }

            Section {
                Link("speech-swift — Apache 2.0", destination: URL(string: "https://github.com/soniqo/speech-swift")!)
                Link("Sparkle — MIT", destination: URL(string: "https://sparkle-project.org/")!)
            } header: {
                Text("Libraries")
            }
        }
        .formStyle(.grouped)
    }
}

struct LanguagePicker: View {
    @Binding var selectedLanguage: String

    var body: some View {
        Picker("Language", selection: $selectedLanguage) {
            Text("Auto-detect").tag("auto")
            Divider()
            ForEach(Constants.sortedLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        }
    }
}

struct ModelRow: View {
    let model: ModelManager.Model
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancelDownload: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(model.sizeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingContent
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded {
                onSelect()
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if model.isDownloading {
            downloadingContent
        } else if model.isDownloaded {
            downloadedContent
        } else {
            downloadButton
        }
    }

    @ViewBuilder
    private var downloadingContent: some View {
        ProgressView(value: model.downloadProgress)
            .progressViewStyle(.linear)
            .frame(width: 80)

        Text("\(Int(model.downloadProgress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 35, alignment: .trailing)

        Button("Cancel") {
            onCancelDownload()
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var downloadedContent: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } else {
            selectButton
        }

        deleteButton
    }

    private var selectButton: some View {
        Button("Select") {
            onSelect()
        }
        .buttonStyle(.borderless)
    }

    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Delete model")
    }

    private var downloadButton: some View {
        Button("Download") {
            onDownload()
        }
        .buttonStyle(.bordered)
    }
}

struct HistoryEntryRow: View {
    let entry: DictationHistoryEntry
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .fontWeight(.semibold)

                Text(entry.transcript.isEmpty ? "No transcript text" : entry.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(entry.modelName) • \(entry.languageDisplayName) • \(entry.durationDisplayText) • \(entry.audioSizeDisplayText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Reveal") {
                onReveal()
            }
            .buttonStyle(.borderless)
        }
    }
}

private extension DictationHistoryEntry {
    var durationDisplayText: String {
        String(format: "%.1fs", duration)
    }

    var audioSizeDisplayText: String {
        ByteCountFormatter.string(fromByteCount: audioByteCount, countStyle: .file)
    }

    var languageDisplayName: String {
        if language == "auto" {
            return "Auto"
        }
        return Constants.sortedLanguages.first { $0.code == language }?.name ?? language
    }
}

#Preview {
    SettingsView(updaterController: UpdaterController(), onAppearAction: {})
}
