import SwiftUI

/// Setup checklist plus a dictation playground for testing the full pipeline.
struct GettingStartedPage: View {
    @AppStorage(AppSettingKey.selectedModel) private var selectedModel = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
    @AppStorage(AppSettingKey.selectedLanguage) private var selectedLanguage = Constants.defaultLanguage
    @AppStorage(AppSettingKey.outputMode) private var outputMode = TypingService.OutputMode.directTyping.rawValue
    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @AppStorage(AppSettingKey.onboardingCompleted) private var onboardingCompleted = false

    @State private var modelManager = ModelManager.shared
    @State private var permissionRefreshTick = false
    @State private var playgroundText = ""

    var body: some View {
        Form {
            Section {
                SetupChecklistView(
                    readiness: setupReadiness,
                    onRequestMicrophone: requestMicrophoneAccess,
                    onOpenAccessibilitySettings: openAccessibilitySettings,
                    onDownloadBaseModel: downloadBaseModel
                )

                Button("Run Setup Again") {
                    runOnboardingAgain()
                }
            } header: {
                Text("Quick Setup")
            } footer: {
                Text("Jabber needs these before dictation feels boringly reliable.")
            }

            Section {
                HStack(spacing: 6) {
                    Text("Press")
                        .foregroundStyle(.secondary)
                    KeycapsView(labels: hotkeyShortcut.keycapLabels)
                    Text("and speak. Your words appear wherever your cursor is.")
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $playgroundText)
                    .font(.body)
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if playgroundText.isEmpty {
                            Text(playgroundPlaceholder)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 1)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Test Playground")
            } footer: {
                Text(isClipboardOutputMode
                    ? "Output mode is set to clipboard — paste with ⌘V after dictating."
                    : "Click the field first so the transcription has somewhere to land.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            modelManager.refreshModels()
            permissionRefreshTick.toggle()
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

    private var isClipboardOutputMode: Bool {
        selectedOutputMode == .clipboard
    }

    private var hotkeyShortcut: HotkeyShortcut {
        HotkeyShortcut(
            keyCode: UInt32(clamping: hotkeyKeyCode),
            modifiers: UInt32(clamping: hotkeyModifiers)
        )
    }

    private var playgroundPlaceholder: String {
        isClipboardOutputMode
            ? "Dictate, then paste your words here with ⌘V…"
            : "Click here, press the hotkey, and say hello…"
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
}
