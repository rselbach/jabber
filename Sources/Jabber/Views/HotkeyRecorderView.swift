import AppKit
import Carbon
import SwiftUI

struct HotkeyRecorderView: View {
    let shortcut: HotkeyShortcut
    let onShortcutChange: (HotkeyShortcut) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(isRecording ? "Press shortcut..." : "Record Shortcut") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                if isRecording {
                    Button("Cancel") {
                        stopRecording()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var helpText: String {
        if isRecording {
            return "Press a key with Command, Control, or Option. A lone modifier like Right Option also works. Escape cancels."
        }
        return "Current shortcut: \(shortcut.displayString)"
    }

    private func startRecording() {
        validationMessage = nil
        NotificationCenter.default.post(
            name: Constants.Notifications.hotkeyCaptureDidBegin,
            object: nil
        )
        isRecording = true
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            self.handleRecordingEvent(event)
        }
        guard let monitor else {
            isRecording = false
            validationMessage = "Could not start shortcut recording."
            NotificationCenter.default.post(
                name: Constants.Notifications.hotkeyCaptureDidEnd,
                object: nil
            )
            return
        }
        eventMonitor = monitor
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard isRecording else { return }
        isRecording = false
        NotificationCenter.default.post(
            name: Constants.Notifications.hotkeyCaptureDidEnd,
            object: nil
        )
    }

    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return event
        }
    }

    /// Capture a modifier key pressed on its own (e.g. Right Option). Only
    /// fires when that modifier is newly pressed and no other modifiers are
    /// held, so combos still fall through to the key-down path.
    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        let keyCode = UInt32(event.keyCode)
        guard HotkeyShortcut.modifierOnlyKeyCodes.contains(keyCode),
              let modifierFlag = HotkeyShortcut.carbonModifier(forKeyCode: keyCode) else {
            return nil
        }

        let heldModifiers = HotkeyShortcut.carbonModifiers(from: event.modifierFlags)
        guard heldModifiers == modifierFlag else { return nil }

        let shortcut = HotkeyShortcut(keyCode: keyCode, modifiers: 0)
        validationMessage = nil
        stopRecording()
        onShortcutChange(shortcut)
        return nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        let captured = HotkeyShortcut.from(event: event)
        if event.keyCode == UInt16(kVK_Escape) {
            validationMessage = nil
            stopRecording()
            return nil
        }

        if let error = captured.validationError {
            validationMessage = error.localizedDescription
            return nil
        }

        validationMessage = nil
        stopRecording()
        onShortcutChange(captured)
        return nil
    }
}
