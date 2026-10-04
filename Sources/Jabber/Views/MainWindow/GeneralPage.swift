import AVFoundation
import SwiftUI

/// Permissions, output, media, and update preferences.
struct GeneralPage: View {
    @ObservedObject var updaterController: UpdaterController

    @AppStorage(AppSettingKey.inputDeviceUID) private var inputDeviceUID = ""
    @AppStorage(AppSettingKey.outputMode) private var outputMode = TypingService.OutputMode.directTyping.rawValue
    @AppStorage(AppSettingKey.pauseMediaDuringRecording) private var pauseMediaDuringRecording = false
    @AppStorage(AppSettingKey.soundFeedbackEnabled) private var soundFeedbackEnabled = true

    @State private var microphoneStatus = AVAuthorizationStatus.notDetermined
    @State private var isAccessibilityTrusted = false
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var inputDeviceRefreshTick = false

    var body: some View {
        Form {
            Section {
                permissionRow(
                    "Microphone",
                    status: .microphone(microphoneStatus),
                    fix: fixMicrophoneAccess
                )
                permissionRow(
                    "Accessibility",
                    status: .accessibility(isTrusted: isAccessibilityTrusted, isNeeded: isAccessibilityNeeded),
                    fix: openAccessibilitySettings
                )
            } header: {
                Text("Permissions")
            }

            Section {
                Picker("Input", selection: $inputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    if isSelectedInputUnavailable {
                        Text("Unavailable Microphone").tag(inputDeviceUID)
                    }
                }

                if isSelectedInputUnavailable {
                    Text("The selected microphone is not connected. Jabber will not fall back to another input.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(inputDeviceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Microphone")
            }

            Section {
                Picker("After transcription", selection: $outputMode) {
                    Text("Copy to clipboard").tag(TypingService.OutputMode.clipboard.rawValue)
                    Text("Type into active app").tag(TypingService.OutputMode.directTyping.rawValue)
                }
                .pickerStyle(.radioGroup)

                if selectedOutputMode == .clipboard {
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
                Toggle("Play sounds when dictation starts and stops", isOn: $soundFeedbackEnabled)
            } header: {
                Text("Feedback")
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

                Button("Check for Updates…") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("Current version: \(AppVersion.displayString)")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            outputMode = TypingService.migratedOutputModeRawValue(outputMode)
            refreshInputDevices()
            refreshPermissions()
        }
        .onChange(of: inputDeviceUID) {
            AudioInputDeviceMonitor.shared.selectionDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.audioInputDevicesDidChange)) { _ in
            refreshInputDevices()
        }
        // Picks up changes made in System Settings once the user is back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func permissionRow(
        _ title: String,
        status: PermissionStatus,
        fix: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(status.needsAttention ? .orange : .secondary)
            }

            Spacer()

            if status.isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                switch status.action {
                case .requestAccess:
                    Button("Allow", action: fix)
                case .openSettings:
                    Button("Open Settings", action: fix)
                case .none:
                    EmptyView()
                }
            }
        }
    }

    /// Typing into apps and lone-key hotkeys both need Accessibility.
    private var isAccessibilityNeeded: Bool {
        selectedOutputMode == .directTyping || TypedSettings.hotkeyShortcut.needsAccessibility
    }

    private func refreshPermissions() {
        microphoneStatus = PermissionService.shared.microphoneAuthorizationStatus()
        isAccessibilityTrusted = PermissionService.shared.refreshAccessibilityPermissionStatus()
    }

    /// Asks the first time; after a denial only System Settings can change it.
    private func fixMicrophoneAccess() {
        guard microphoneStatus == .notDetermined else {
            PermissionService.shared.openPrivacySettings(for: .microphone)
            return
        }
        Task {
            _ = await PermissionService.shared.requestMicrophonePermission()
            refreshPermissions()
        }
    }

    /// Prompting first adds Jabber to the Accessibility list, so the user
    /// only has to switch it on.
    private func openAccessibilitySettings() {
        _ = PermissionService.shared.requestAccessibilityPermission()
        PermissionService.shared.openPrivacySettings(for: .accessibility)
        refreshPermissions()
    }

    private var selectedOutputMode: TypingService.OutputMode {
        TypingService.OutputMode(rawValue: TypingService.migratedOutputModeRawValue(outputMode)) ?? .directTyping
    }

    private var isSelectedInputUnavailable: Bool {
        !inputDeviceUID.isEmpty && !inputDevices.contains { $0.uid == inputDeviceUID }
    }

    private var inputDeviceDescription: String {
        _ = inputDeviceRefreshTick
        if inputDeviceUID.isEmpty {
            let name = AudioInputDeviceMonitor.shared.defaultInputDevice?.name ?? "the macOS default"
            return "Follows the input selected in macOS. Currently using \(name)."
        }

        let name = inputDevices.first { $0.uid == inputDeviceUID }?.name ?? "the selected microphone"
        return "Jabber will keep using \(name) when the system default changes."
    }

    private func refreshInputDevices() {
        inputDevices = AudioInputDeviceMonitor.shared.devices
        inputDeviceRefreshTick.toggle()
    }
}

/// App version string sourced from the bundle, with a fallback for
/// development builds run outside an app bundle.
enum AppVersion {
    static var displayString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
