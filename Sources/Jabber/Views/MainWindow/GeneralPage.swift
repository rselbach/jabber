import SwiftUI

/// Output, media, and update preferences.
struct GeneralPage: View {
    @ObservedObject var updaterController: UpdaterController

    @AppStorage(AppSettingKey.inputDeviceUID) private var inputDeviceUID = ""
    @AppStorage(AppSettingKey.outputMode) private var outputMode = TypingService.OutputMode.directTyping.rawValue
    @AppStorage(AppSettingKey.pauseMediaDuringRecording) private var pauseMediaDuringRecording = false
    @AppStorage(AppSettingKey.soundFeedbackEnabled) private var soundFeedbackEnabled = true

    @State private var permissionRefreshTick = false
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var inputDeviceRefreshTick = false

    var body: some View {
        Form {
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

                if selectedOutputMode == .directTyping {
                    Button("Open Accessibility Settings") {
                        PermissionService.shared.openPrivacySettings(for: .accessibility)
                    }
                    .buttonStyle(.borderless)

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
            permissionRefreshTick.toggle()
        }
        .onChange(of: inputDeviceUID) {
            AudioInputDeviceMonitor.shared.selectionDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.audioInputDevicesDidChange)) { _ in
            refreshInputDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshTick.toggle()
        }
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

    private var isAccessibilityTrusted: Bool {
        _ = permissionRefreshTick
        return PermissionService.shared.hasAccessibilityPermission()
    }
}

/// App version string sourced from the bundle, with a fallback for
/// development builds run outside an app bundle.
enum AppVersion {
    static var displayString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
