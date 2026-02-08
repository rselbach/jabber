import Carbon
import Foundation
import os

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "HotkeyManager")

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onRegistrationFailure: ((OSStatus) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        let hotKeyID = EventHotKeyID(
            signature: OSType(fourCharCode: "JBBR")!,
            id: 1
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            logger.error("Failed to register hotkey with status: \(status)")
            onRegistrationFailure?(status)
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, refcon) -> OSStatus in
                guard let refcon, let event else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let kind = GetEventKind(event)

                if kind == UInt32(kEventHotKeyPressed) {
                    manager.onKeyDown?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    manager.onKeyUp?()
                }

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            refcon,
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("Failed to install hotkey event handler with status: \(status)")
            onRegistrationFailure?(status)
        }
    }

    // MARK: - Saved Hotkey

    static func savedKeyCode() -> UInt32 {
        let value = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        return value != 0 ? UInt32(value) : Constants.Hotkey.defaultKeyCode
    }

    static func savedModifiers() -> UInt32 {
        if UserDefaults.standard.object(forKey: "hotkeyModifiers") != nil {
            return UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        }
        return Constants.Hotkey.defaultModifiers
    }

    static func saveHotkey(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotkeyModifiers")
        NotificationCenter.default.post(name: Constants.Notifications.hotkeyDidChange, object: nil)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
        NotificationCenter.default.post(name: Constants.Notifications.hotkeyDidChange, object: nil)
    }

    // MARK: - Display Strings

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let modifierString = modifierSymbols(modifiers)
        let keyString = keyName(for: keyCode)
        return modifierString + keyString
    }

    static func modifierSymbols(_ modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        // Letters
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x32: return "`"
        // Special keys
        case 0x24: return "↩"  // Return
        case 0x30: return "⇥"  // Tab
        case 0x31: return "Space"
        case 0x33: return "⌫"  // Delete
        case 0x35: return "⎋"  // Escape
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x69: return "F13"
        case 0x6B: return "F14"
        case 0x71: return "F15"
        case 0x6A: return "F16"
        case 0x40: return "F17"
        case 0x4F: return "F18"
        case 0x50: return "F19"
        case 0x5A: return "F20"
        case 0x7B: return "←"  // Left arrow
        case 0x7C: return "→"  // Right arrow
        case 0x7D: return "↓"  // Down arrow
        case 0x7E: return "↑"  // Up arrow
        case 0x73: return "↖"  // Home
        case 0x77: return "↘"  // End
        case 0x74: return "⇞"  // Page Up
        case 0x79: return "⇟"  // Page Down
        default: return "Key \(keyCode)"
        }
    }
}

private extension OSType {
    init?(fourCharCode: String) {
        guard fourCharCode.utf8.count == 4 else {
            return nil
        }
        var result: OSType = 0
        for char in fourCharCode.utf8 {
            result = (result << 8) + OSType(char)
        }
        self = result
    }
}
