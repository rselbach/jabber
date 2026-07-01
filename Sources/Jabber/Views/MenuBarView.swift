import AppKit
import SwiftUI

struct MenuBarView: View {
    @AppStorage(AppSettingKey.selectedModel) private var selectedModel = AppMode.baseModelId
    @AppStorage(AppSettingKey.selectedLanguage) private var selectedLanguage = Constants.defaultLanguage
    @AppStorage(AppSettingKey.outputMode) private var outputMode = TypingService.OutputMode.directTyping.rawValue
    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @State private var modelManager = ModelManager.shared
    @State private var permissionRefreshTick = false
    @ObservedObject var updaterController: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber")
                .font(.headline)

            Divider()

            if !setupReadiness.isComplete {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finish Setup")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    SetupChecklistView(
                        readiness: setupReadiness,
                        showsCompleteMessage: false,
                        onRequestMicrophone: requestMicrophoneAccess,
                        onOpenAccessibilitySettings: openAccessibilitySettings,
                        onDownloadBaseModel: downloadBaseModel
                    )
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Press \(hotkeyDisplay) to dictate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if modelManager.downloadedModels.isEmpty {
                    Text("No models downloaded")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Model:")
                        Picker("", selection: Binding(
                            get: { selectedModel },
                            set: { newValue in
                                if modelManager.selectModel(newValue) {
                                    selectedModel = newValue
                                }
                            }
                        )) {
                            ForEach(modelManager.downloadedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Language:")
                        LanguagePicker(selectedLanguage: $selectedLanguage)
                            .labelsHidden()
                    }
                }
            }

            Divider()

            Button("Check for Updates...") {
                updaterController.checkForUpdates()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(!updaterController.canCheckForUpdates)

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            refreshMenuState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshTick.toggle()
        }
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

    private var hotkeyDisplay: String {
        HotkeyShortcut(
            keyCode: UInt32(max(0, hotkeyKeyCode)),
            modifiers: UInt32(max(0, hotkeyModifiers))
        ).displayString
    }

    private func refreshMenuState() {
        outputMode = TypingService.migratedOutputModeRawValue(outputMode)
        permissionRefreshTick.toggle()
        _ = modelManager.migrateSelectedModelIfNeeded()
        modelManager.refreshModels()

        if !modelManager.downloadedModels.contains(where: { $0.id == selectedModel }),
           let fallbackModel = modelManager.downloadedModels.first?.id {
            if modelManager.selectModel(fallbackModel) {
                selectedModel = fallbackModel
            }
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
}

#Preview {
    MenuBarView(updaterController: UpdaterController())
}
