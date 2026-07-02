import AppKit
import Carbon
import SwiftUI

struct HotkeyRecorderView: View {
    let shortcut: HotkeyShortcut
    let onShortcutChange: (HotkeyShortcut) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var validationMessage: String?
    @State private var recorder = HotkeyRecorderReducer()

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
        recorder.reset()
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
            let outcome = recorder.flagsChanged(
                keyCode: UInt32(event.keyCode),
                heldModifiers: HotkeyShortcut.carbonModifiers(from: event.modifierFlags)
            )
            return apply(outcome)
        case .keyDown:
            let outcome = recorder.keyDown(
                keyCode: UInt32(event.keyCode),
                modifiers: HotkeyShortcut.carbonModifiers(from: event.modifierFlags),
                isEscape: event.keyCode == UInt16(kVK_Escape)
            )
            return apply(outcome)
        default:
            return event
        }
    }

    /// Maps a reducer decision to UI side effects. Returns the event to forward
    /// to the next monitor (always `nil` during recording — events are
    /// swallowed so the host app does not receive them).
    @discardableResult
    private func apply(_ outcome: HotkeyRecorderReducer.Outcome) -> NSEvent? {
        switch outcome {
        case .wait:
            return nil
        case .cancel:
            validationMessage = nil
            stopRecording()
            return nil
        case .commitModifierOnly(let keyCode):
            // Validation already permits bare modifiers; commit directly.
            commit(HotkeyShortcut(keyCode: keyCode, modifiers: 0))
            return nil
        case .commitCombo(let keyCode, let modifiers):
            let captured = HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
            if let error = captured.validationError {
                // Keep recording so the user can try a different combo, but
                // swallow the key so it does not reach the host app.
                validationMessage = error.localizedDescription
                return nil
            }
            commit(captured)
            return nil
        }
    }

    private func commit(_ shortcut: HotkeyShortcut) {
        validationMessage = nil
        stopRecording()
        onShortcutChange(shortcut)
    }
}

/// Pure decision logic for the shortcut recorder.
///
/// Extracted from `HotkeyRecorderView` so the modifier-vs-combo rules are unit
/// testable without firing real `NSEvent`s. The view feeds it raw key code +
/// modifier flag inputs and maps the returned `Outcome` to recording side
/// effects.
///
/// Behaviour (mirrors the FluidVoice recorder):
/// - Pressing a standalone modifier on its own (no other modifiers held) arms a
///   pending modifier-only candidate but does NOT commit. This is what lets
///   combos like Left Option+Space still record: Space arrives as a key-down
///   before the modifier is released.
/// - A non-modifier key-down finalizes a combo using the currently held
///   modifier flags (e.g. Option+Space). Any pending modifier-only candidate is
///   dropped, since the user is clearly building a combo.
/// - Releasing the armed modifier — with nothing else still held and no key
///   having intervened — finalizes the modifier-only shortcut (e.g. Right
///   Option).
/// - Escape always cancels.
struct HotkeyRecorderReducer: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        /// No decision yet; keep recording.
        case wait
        /// A lone modifier was pressed and released with no key-down in between.
        case commitModifierOnly(keyCode: UInt32)
        /// A key-down arrived; finalize a combo from its key code + held flags.
        case commitCombo(keyCode: UInt32, modifiers: UInt32)
        /// Escape was pressed; abort recording.
        case cancel
    }

    /// Physical key code of the modifier currently armed as a modifier-only
    /// candidate, or `nil` when no solo modifier is being tracked.
    private(set) var pendingModifierKeyCode: UInt32?

    mutating func reset() {
        pendingModifierKeyCode = nil
    }

    /// Process a flags-changed event.
    /// - Parameters:
    ///   - keyCode: Physical key code of the modifier that changed.
    ///   - heldModifiers: Carbon modifier flags currently held (aggregate).
    mutating func flagsChanged(keyCode: UInt32, heldModifiers: UInt32) -> Outcome {
        guard HotkeyShortcut.modifierOnlyKeyCodes.contains(keyCode),
              let modifierFlag = HotkeyShortcut.carbonModifier(forKeyCode: keyCode) else {
            // Non-modifier flag change (e.g. Caps Lock): ignore, keep waiting.
            return .wait
        }

        let isDown = heldModifiers & modifierFlag != 0
        if isDown {
            // Only a solo press (this modifier and nothing else) arms a
            // modifier-only candidate. Any other modifier held means the user is
            // stacking modifiers for a combo, which the key-down path finalizes.
            if heldModifiers == modifierFlag {
                pendingModifierKeyCode = keyCode
            }
            return .wait
        }

        // Release. Finalize modifier-only only if this exact key was the armed
        // candidate and nothing else is still held. Otherwise just clear state.
        let pending = pendingModifierKeyCode
        pendingModifierKeyCode = nil
        guard keyCode == pending, heldModifiers == 0 else {
            return .wait
        }
        return .commitModifierOnly(keyCode: keyCode)
    }

    /// Process a key-down event.
    /// - Parameters:
    ///   - keyCode: Physical key code of the pressed key.
    ///   - modifiers: Carbon modifier flags held at the time of the press.
    ///   - isEscape: `true` when the key is Escape.
    mutating func keyDown(keyCode: UInt32, modifiers: UInt32, isEscape: Bool) -> Outcome {
        // Any key-down ends the modifier-only intent: the user is either typing
        // a combo or cancelling.
        pendingModifierKeyCode = nil
        if isEscape {
            return .cancel
        }
        return .commitCombo(keyCode: keyCode, modifiers: modifiers)
    }
}
