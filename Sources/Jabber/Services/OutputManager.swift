import AppKit
import Carbon
import ApplicationServices
import os

@MainActor
final class OutputManager {
    enum OutputMode: String {
        case clipboard
        case pasteInPlace = "paste"
    }

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "OutputManager")
    private static let pasteDelay: TimeInterval = 0.05

    var mode: OutputMode {
        let modeString = UserDefaults.standard.string(forKey: "outputMode") ?? "paste"
        return OutputMode(rawValue: modeString) ?? .pasteInPlace
    }

    func output(_ text: String) {
        let didCopyToClipboard = copyToClipboard(text)
        guard didCopyToClipboard else {
            NotificationService.shared.showError(
                title: "Copy Failed",
                message: "Could not copy transcription to clipboard.",
                critical: false
            )
            return
        }

        guard Self.shouldAttemptPaste(mode: mode, didCopyToClipboard: didCopyToClipboard) else {
            return
        }

        guard checkAccessibilityPermission() else {
            logger.warning("Accessibility permission not granted, text copied to clipboard only")
            Task { @MainActor in
                NotificationService.shared.showWarning(
                    title: "Accessibility Permission Required",
                    message: "Text was copied to clipboard. Grant accessibility permission in System Settings to enable auto-paste."
                )
            }
            return
        }

        sendPaste()
    }

    static func shouldAttemptPaste(mode: OutputMode, didCopyToClipboard: Bool) -> Bool {
        didCopyToClipboard && mode == .pasteInPlace
    }

    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Prompt user to grant permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            // Check again - permission might be granted now
            // Note: If just granted, may require app relaunch to take effect
            return AXIsProcessTrusted()
        }

        return true
    }

    private func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        if !success {
            logger.warning("Failed to copy text to clipboard")
        }
        return success
    }

    private func sendPaste() {
        // Small delay to ensure the target app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) { [weak self] in
            guard let self else { return }

            // Synthesize Cmd+V
            let src = CGEventSource(stateID: .hidSystemState)

            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.v, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: KeyCode.v, keyDown: false) else {
                self.logger.error("Failed to create CGEvent for paste operation")
                Task { @MainActor in
                    NotificationService.shared.showError(
                        title: "Paste Failed",
                        message: "Could not simulate paste command. Text is in clipboard.",
                        critical: false
                    )
                }
                return
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

// Virtual key codes for keyboard events
private enum KeyCode {
    static let v: CGKeyCode = 0x09
}
