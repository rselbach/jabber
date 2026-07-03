import SwiftUI

/// Output, media, and update preferences.
struct GeneralPage: View {
    @ObservedObject var updaterController: UpdaterController

    @AppStorage(AppSettingKey.outputMode) private var outputMode = TypingService.OutputMode.directTyping.rawValue
    @AppStorage(AppSettingKey.pauseMediaDuringRecording) private var pauseMediaDuringRecording = false

    @State private var permissionRefreshTick = false

    var body: some View {
        Form {
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
            permissionRefreshTick.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefreshTick.toggle()
        }
    }

    private var selectedOutputMode: TypingService.OutputMode {
        TypingService.OutputMode(rawValue: TypingService.migratedOutputModeRawValue(outputMode)) ?? .directTyping
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
