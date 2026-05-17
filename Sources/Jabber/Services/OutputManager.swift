import AppKit
import Carbon
import ApplicationServices
import os

@MainActor
final class OutputManager {
    private let permissionService = PermissionService.shared
    enum OutputMode: String {
        case clipboard
        case pasteInPlace = "paste"

        var requiresAccessibilityPermission: Bool {
            self == .pasteInPlace
        }
    }

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "OutputManager")
    private static let pasteDelay: TimeInterval = 0.05
    private static let clipboardRestoreDelay: TimeInterval = 0.5

    var mode: OutputMode {
        OutputMode(rawValue: TypedSettings[.outputMode]) ?? .pasteInPlace
    }

    var requiresAccessibilityPermission: Bool {
        mode.requiresAccessibilityPermission
    }

    func output(_ text: String) {
        let selectedMode = mode
        let pasteboard = NSPasteboard.general
        let previousClipboard = selectedMode == .pasteInPlace
            ? PasteboardSnapshot.capture(from: pasteboard)
            : nil

        let didCopyToClipboard = copyToClipboard(text, pasteboard: pasteboard)
        guard didCopyToClipboard else {
            if let previousClipboard {
                restoreClipboard(previousClipboard, expectedChangeCount: pasteboard.changeCount)
            }
            NotificationService.shared.showError(
                title: "Copy Failed",
                message: "Could not copy transcription to clipboard.",
                critical: false
            )
            return
        }

        guard Self.shouldAttemptPaste(mode: selectedMode, didCopyToClipboard: didCopyToClipboard) else {
            return
        }

        guard permissionService.requestAccessibilityPermission() else {
            logger.warning("Accessibility permission not granted, text copied to clipboard only")
            Task { @MainActor in
                NotificationService.shared.showPermissionWarning(
                    title: "Accessibility Permission Required",
                    message: "Text was copied to clipboard. Grant accessibility permission to enable auto-paste.",
                    section: .accessibility
                )
            }
            return
        }

        sendPaste(
            restoring: previousClipboard,
            expectedPasteboardChangeCount: pasteboard.changeCount
        )
    }

    static func shouldAttemptPaste(mode: OutputMode, didCopyToClipboard: Bool) -> Bool {
        didCopyToClipboard && mode == .pasteInPlace
    }

    static func requiresAccessibilityPermission(mode: OutputMode) -> Bool {
        mode.requiresAccessibilityPermission
    }

    private func copyToClipboard(_ text: String, pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        if !success {
            logger.warning("Failed to copy text to clipboard")
        }
        return success
    }

    private func sendPaste(
        restoring previousClipboard: PasteboardSnapshot?,
        expectedPasteboardChangeCount: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) { [weak self] in
            guard let self else { return }

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

            guard let previousClipboard else { return }
            self.scheduleClipboardRestore(
                previousClipboard,
                expectedChangeCount: expectedPasteboardChangeCount
            )
        }
    }

    private func scheduleClipboardRestore(
        _ snapshot: PasteboardSnapshot,
        expectedChangeCount: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clipboardRestoreDelay) { [weak self] in
            self?.restoreClipboard(snapshot, expectedChangeCount: expectedChangeCount)
        }
    }

    private func restoreClipboard(_ snapshot: PasteboardSnapshot, expectedChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount else {
            logger.info("Skipping clipboard restore because the pasteboard changed")
            return
        }

        guard snapshot.restore(to: pasteboard) else {
            logger.warning("Failed to restore previous clipboard contents")
            return
        }
    }
}

struct PasteboardSnapshot: Equatable {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems ?? []
        let capturedItems = items.map { item in
            var capturedTypes: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    capturedTypes[type] = data
                }
            }
            return capturedTypes
        }

        return PasteboardSnapshot(items: capturedItems)
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }

        var pasteboardItems: [NSPasteboardItem] = []
        pasteboardItems.reserveCapacity(items.count)

        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item {
                guard pasteboardItem.setData(data, forType: type) else { return false }
            }
            pasteboardItems.append(pasteboardItem)
        }

        return pasteboard.writeObjects(pasteboardItems)
    }
}

private enum KeyCode {
    static let v: CGKeyCode = 0x09
}
