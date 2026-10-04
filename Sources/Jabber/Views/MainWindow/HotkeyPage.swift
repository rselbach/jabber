import SwiftUI

/// Dictation hotkey configuration: shortcut recorder and activation mode.
struct HotkeyPage: View {
    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @AppStorage(AppSettingKey.hotkeyActivationMode) private var hotkeyActivationMode = HotkeyActivationMode.defaultMode.rawValue
    @State private var globeKeyAction = GlobeKeyAction.unknown

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Press to talk")
                    Spacer()
                    KeycapsView(labels: hotkeyShortcut.keycapLabels)
                }

                if hotkeyShortcut == HotkeyPreset.fn.shortcut, let warning = globeKeyAction.fnHotkeyWarning {
                    GlobeKeyWarning(message: warning)
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
                Text("Shortcut")
            } footer: {
                Text("Shortcuts must include Command, Control, or Option — or use a single modifier key like Right Option or Fn on its own — so Jabber does not steal every innocent keystroke like a gremlin.")
            }

            Section {
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
            } header: {
                Text("Activation")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hotkeyActivationMode = selectedHotkeyActivationMode.rawValue
            globeKeyAction = GlobeKeyAction.current()
        }
        // Picks up a change made in Keyboard settings once the user is back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            globeKeyAction = GlobeKeyAction.current()
        }
    }

    private var hotkeyShortcut: HotkeyShortcut {
        HotkeyShortcut(
            keyCode: UInt32(clamping: hotkeyKeyCode),
            modifiers: UInt32(clamping: hotkeyModifiers)
        )
    }

    private var selectedHotkeyActivationMode: HotkeyActivationMode {
        HotkeyActivationMode(rawValue: hotkeyActivationMode) ?? .defaultMode
    }

    private func applyHotkeyShortcut(_ shortcut: HotkeyShortcut) {
        hotkeyKeyCode = Int(shortcut.keyCode)
        hotkeyModifiers = Int(shortcut.modifiers)
        NotificationCenter.default.post(
            name: Constants.Notifications.hotkeyShortcutDidChange,
            object: shortcut
        )
    }

    private func applyHotkeyActivationModeRawValue(_ rawValue: String) {
        let mode = HotkeyActivationMode(rawValue: rawValue) ?? .defaultMode
        if hotkeyActivationMode != mode.rawValue {
            hotkeyActivationMode = mode.rawValue
        }
    }
}
