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
            return "Press a key with Command, Control, or Option. Escape cancels."
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
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
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
