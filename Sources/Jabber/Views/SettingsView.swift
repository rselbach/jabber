import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updaterController: UpdaterController

    @AppStorage(AppSettingKey.selectedModel) private var selectedModel = AppMode.baseModelId
    @AppStorage(AppSettingKey.outputMode) private var outputMode = OutputManager.OutputMode.pasteInPlace.rawValue
    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @AppStorage(AppSettingKey.vocabularyPrompt) private var vocabularyPrompt = ""
    @AppStorage(AppSettingKey.selectedLanguage) private var selectedLanguage = Constants.defaultLanguage

    @State private var modelManager = ModelManager.shared
    @State private var permissionRefreshTick = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pendingDeleteModelId: String?
    @State private var pendingDeleteModelName: String?

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
        }
        .frame(width: 520, height: 560)
        .onAppear {
            permissionRefreshTick.toggle()
            _ = modelManager.migrateSelectedModelIfNeeded()
            modelManager.refreshModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshTick.toggle()
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { }
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

    private var selectedOutputMode: OutputManager.OutputMode {
        OutputManager.OutputMode(rawValue: outputMode) ?? .pasteInPlace
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

    private var generalTab: some View {
        Form {
            setupSection

            Section {
                Picker("After transcription", selection: $outputMode) {
                    Text("Copy to clipboard").tag(OutputManager.OutputMode.clipboard.rawValue)
                    Text("Paste into active app").tag(OutputManager.OutputMode.pasteInPlace.rawValue)
                }
                .pickerStyle(.radioGroup)

                if outputMode == OutputManager.OutputMode.pasteInPlace.rawValue {
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

                Button("Reset to ⌥ Space") {
                    applyHotkeyShortcut(.defaultShortcut)
                }
                .buttonStyle(.borderless)
                .disabled(hotkeyShortcut == .defaultShortcut)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Shortcuts must include Command, Control, or Option so Jabber does not steal every innocent keystroke like a gremlin.")
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
        if !modelManager.startDownload(AppMode.baseModelId) {
            modelManager.refreshModels()
        }
    }

    private func applyHotkeyShortcut(_ shortcut: HotkeyShortcut) {
        hotkeyKeyCode = Int(shortcut.keyCode)
        hotkeyModifiers = Int(shortcut.modifiers)
        NotificationCenter.default.post(
            name: Constants.Notifications.hotkeyDidChange,
            object: shortcut
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

#Preview {
    SettingsView(updaterController: UpdaterController())
}
