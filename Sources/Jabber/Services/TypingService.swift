import AppKit
@preconcurrency import ApplicationServices
import os

@MainActor
final class TypingService {
    enum OutputMode: String {
        case clipboard
        case directTyping

        var requiresAccessibilityPermission: Bool {
            self == .directTyping
        }
    }

    private let permissionService = PermissionService.shared
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "TypingService")
    private static let pasteDelay: TimeInterval = 0.05
    private static let clipboardRestoreDelay: TimeInterval = 0.5
    /// CGEvent.keyboardSetUnicodeString (CGEventKeyboardSetUnicodeString) silently
    /// truncates payloads beyond 20 UTF-16 code units at runtime, garbling injected
    /// text. CoreGraphics' CGEvent.h documents the manual override but not the cap;
    /// the 20-UniChar limit is the long-standing OS behavior relied on by projects
    /// such as Hammerspoon and Karabiner. See CGEvent.h (CGEventKeyboardSetUnicodeString).
    private static let cgEventUnicodeChunkSize = 20

    var mode: OutputMode {
        let rawValue = TypedSettings[.outputMode]
        return OutputMode(rawValue: Self.migratedOutputModeRawValue(rawValue)) ?? .directTyping
    }

    var requiresAccessibilityPermission: Bool {
        mode.requiresAccessibilityPermission
    }

    static func migratedOutputModeRawValue(_ rawValue: String) -> String {
        switch rawValue {
        case "paste":
            return OutputMode.directTyping.rawValue
        case OutputMode.clipboard.rawValue:
            return OutputMode.clipboard.rawValue
        default:
            return OutputMode.directTyping.rawValue
        }
    }

    static func requiresAccessibilityPermission(mode: OutputMode) -> Bool {
        mode.requiresAccessibilityPermission
    }

    static func captureFocusedProcessID() -> pid_t? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard result == .success, let focusedElementRef else { return nil }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else { return nil }

        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(focusedElement, &pid)
        guard pidResult == .success, pid > 0 else { return nil }

        return pid
    }

    /// Resolves the app icon for the process Jabber will type into.
    /// Falls back to the frontmost app when the PID is missing or unresolvable,
    /// and never returns Jabber's own icon.
    static func appIcon(forTargetProcessID pid: pid_t?) -> NSImage? {
        let ownBundleID = Bundle.main.bundleIdentifier

        if let pid, pid > 0,
           let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier != ownBundleID {
            return app.icon
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != ownBundleID {
            return frontmost.icon
        }

        return nil
    }

    func output(_ text: String, targetProcessID: pid_t?) {
        switch mode {
        case .clipboard:
            copyOnly(text)
        case .directTyping:
            outputViaDirectTyping(text, targetProcessID: targetProcessID)
        }
    }

    static func unicodeChunks(for text: String) -> [[UInt16]] {
        let utf16Array = Array(text.utf16)
        guard !utf16Array.isEmpty else { return [] }

        var chunks: [[UInt16]] = []
        var chunkStart = 0
        while chunkStart < utf16Array.count {
            let chunkEnd = unicodeChunkEnd(in: utf16Array, start: chunkStart)
            chunks.append(Array(utf16Array[chunkStart ..< chunkEnd]))
            chunkStart = chunkEnd
        }
        return chunks
    }

    private func outputViaDirectTyping(_ text: String, targetProcessID: pid_t?) {
        switch DirectTypingFallback.resolve(
            hasAccessibilityPermission: permissionService.hasAccessibilityPermission()
        ) {
        case .pasteWithRestore:
            if let targetProcessID,
               insertUnicodeText(text, targetProcessID: targetProcessID) {
                return
            }

            if insertTextViaAccessibility(text, targetProcessID: targetProcessID) {
                return
            }

            if insertUnicodeTextViaHID(text) {
                return
            }

            pasteViaClipboard(text)
        case .copyOnlyWithNotice:
            // Accessibility not granted: a synthetic Cmd+V is silently dropped
            // by macOS for untrusted processes, and the scheduled clipboard
            // restore would then overwrite the transcript with the prior
            // clipboard contents. Copy without restoring and tell the user.
            logger.warning("Accessibility permission not granted; copying transcript without paste")
            copyOnly(text)
            NotificationService.shared.showWarning(
                title: "Transcript Copied to Clipboard",
                message: "Grant Accessibility permission in Privacy & Security to enable direct typing into apps."
            )
        }
    }

    private func copyOnly(_ text: String) {
        let pasteboard = NSPasteboard.general
        guard copyToClipboard(text, pasteboard: pasteboard) else {
            NotificationService.shared.showError(
                title: "Copy Failed",
                message: "Could not copy transcription to clipboard.",
                critical: false
            )
            return
        }
    }

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousClipboard = PasteboardSnapshot.capture(from: pasteboard)

        guard copyToClipboard(text, pasteboard: pasteboard) else {
            restoreClipboard(previousClipboard, expectedChangeCount: pasteboard.changeCount)
            NotificationService.shared.showError(
                title: "Copy Failed",
                message: "Could not copy transcription to clipboard.",
                critical: false
            )
            return
        }

        sendPaste(
            restoring: previousClipboard,
            expectedPasteboardChangeCount: pasteboard.changeCount
        )
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
                // The transcript is already on the clipboard. Leave it there
                // so the user can paste manually — restoring the previous
                // clipboard here would silently discard the transcript while
                // the notification claims it is available.
                NotificationService.shared.showError(
                    title: "Paste Failed",
                    message: "Could not simulate paste command. Text is in clipboard.",
                    critical: false
                )
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
            NotificationService.shared.showWarning(
                title: "Clipboard Restore Failed",
                message: "Could not restore your previous clipboard contents. They may have been lost."
            )
            return
        }
    }

    private func insertUnicodeText(_ text: String, targetProcessID: pid_t) -> Bool {
        guard targetProcessID > 0 else { return false }
        return postUnicodeChunks(for: text) { event in
            event.postToPid(targetProcessID)
        }
    }

    private func insertUnicodeTextViaHID(_ text: String) -> Bool {
        postUnicodeChunks(for: text) { event in
            event.post(tap: .cghidEventTap)
        }
    }

    private func postUnicodeChunks(for text: String, post: (CGEvent) -> Void) -> Bool {
        let chunks = Self.unicodeChunks(for: text)
        guard !chunks.isEmpty else { return true }

        // Pre-build every (keyDown, keyUp) pair before posting any of them.
        // If we posted inline and a CGEvent failed to allocate partway through,
        // earlier chunks would already be delivered to the target app and the
        // caller's fallback (AX insert / HID / clipboard paste) would re-inject
        // the entire transcript on top of them, garbling the output.
        var events: [(down: CGEvent, up: CGEvent)] = []
        events.reserveCapacity(chunks.count)

        for chunk in chunks {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                logger.error("Failed to create CGEvent for unicode text insertion")
                return false
            }

            chunk.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }

            events.append((down: keyDown, up: keyUp))
        }

        for event in events {
            post(event.down)
            post(event.up)
        }

        return true
    }

    private func insertTextViaAccessibility(_ text: String, targetProcessID: pid_t?) -> Bool {
        guard let element = focusedTextElement(targetProcessID: targetProcessID) else { return false }
        guard let currentValue = stringValue(from: element) else { return false }
        guard var selectedRange = selectedTextRange(from: element) else { return false }

        let currentNSString = currentValue as NSString
        let maxLength = currentNSString.length
        let location = max(0, min(selectedRange.location, maxLength))
        let length = max(0, min(selectedRange.length, maxLength - location))
        selectedRange = CFRange(location: location, length: length)

        let updatedValue = NSMutableString(string: currentValue)
        updatedValue.replaceCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: text
        )

        let setValueResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedValue as CFString
        )
        guard setValueResult == .success else {
            logger.info("Accessibility text insertion failed with result: \(setValueResult.rawValue)")
            return false
        }

        let insertedLength = (text as NSString).length
        var newRange = CFRange(location: selectedRange.location + insertedLength, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &newRange) else {
            logger.warning("Failed to create AXValue for updated selected text range")
            return true
        }

        let setRangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        if setRangeResult != .success {
            logger.warning("Failed to update selected text range after insertion: \(setRangeResult.rawValue)")
        }

        return true
    }

    private func focusedTextElement(targetProcessID: pid_t?) -> AXUIElement? {
        if let targetProcessID, targetProcessID > 0 {
            let appElement = AXUIElementCreateApplication(targetProcessID)
            return axElementAttribute(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString)
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        return axElementAttribute(from: systemWideElement, attribute: kAXFocusedUIElementAttribute as CFString)
    }

    private func axElementAttribute(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func stringValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let string = value as? String else { return nil }
        return string
    }

    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }

    private static func unicodeChunkEnd(in utf16Array: [UInt16], start: Int) -> Int {
        var end = min(start + cgEventUnicodeChunkSize, utf16Array.count)
        if end < utf16Array.count,
           end > start,
           isHighSurrogate(utf16Array[end - 1]),
           isLowSurrogate(utf16Array[end]) {
            end -= 1
        }
        return max(end, start + 1)
    }

    private static func isHighSurrogate(_ value: UInt16) -> Bool {
        (0xD800 ... 0xDBFF).contains(value)
    }

    private static func isLowSurrogate(_ value: UInt16) -> Bool {
        (0xDC00 ... 0xDFFF).contains(value)
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
        guard !items.isEmpty else {
            pasteboard.clearContents()
            return true
        }

        // Build the pasteboard items first, *before* clearing the live
        // pasteboard. `setData` can fail for type-mismatch reasons; if we
        // cleared first (as the previous version did) a failure here would
        // leave the pasteboard empty and destroy the user's original contents.
        var pasteboardItems: [NSPasteboardItem] = []
        pasteboardItems.reserveCapacity(items.count)

        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item {
                guard pasteboardItem.setData(data, forType: type) else { return false }
            }
            pasteboardItems.append(pasteboardItem)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects(pasteboardItems)
    }
}

private enum KeyCode {
    static let v: CGKeyCode = 0x09
}

/// Decides how `outputViaDirectTyping` delivers text once the preferred
/// Accessibility-based insertion methods are off the table.
///
/// When Accessibility isn't granted, the previous behavior fell through to
/// `pasteViaClipboard`, which posts a synthetic Cmd+V. macOS silently drops
/// that event for untrusted processes, and ~500ms later the clipboard restore
/// overwrites the transcript with the prior clipboard contents — net effect:
/// nothing typed, transcript lost, no feedback. The copy-only path copies
/// without scheduling a restore, so the transcript survives in the clipboard
/// and the user is told why direct typing didn't happen.
enum DirectTypingFallback {
    enum Delivery: Equatable {
        /// Post a synthetic Cmd+V and restore the previous clipboard.
        case pasteWithRestore
        /// Copy to the clipboard without restoring, and surface a
        /// user-visible notification explaining what happened.
        case copyOnlyWithNotice
    }

    static func resolve(hasAccessibilityPermission hasPermission: Bool) -> Delivery {
        hasPermission ? .pasteWithRestore : .copyOnlyWithNotice
    }
}
