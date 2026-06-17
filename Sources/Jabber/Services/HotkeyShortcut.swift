import AppKit
import Carbon
import Foundation

struct HotkeyShortcut: Equatable, Sendable {
    enum ValidationError: Equatable, LocalizedError {
        case missingRequiredModifier
        case escapeKey

        var errorDescription: String? {
            switch self {
            case .missingRequiredModifier:
                return "Shortcut must include Command, Control, or Option."
            case .escapeKey:
                return "Escape is reserved for cancelling shortcut recording."
            }
        }
    }

    static let defaultShortcut = HotkeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        Self.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    var validationError: ValidationError? {
        Self.validationError(keyCode: keyCode, modifiers: modifiers)
    }

    static func validationError(
        keyCode: UInt32,
        modifiers: UInt32
    ) -> ValidationError? {
        if keyCode == UInt32(kVK_Escape) {
            return .escapeKey
        }

        let requiredModifiers = UInt32(cmdKey | controlKey | optionKey)
        guard modifiers & requiredModifiers != 0 else {
            return .missingRequiredModifier
        }

        return nil
    }

    static func from(event: NSEvent) -> HotkeyShortcut {
        HotkeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(from: event.modifierFlags)
        )
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0

        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return modifiers
    }

    private static func displayString(
        keyCode: UInt32,
        modifiers: UInt32
    ) -> String {
        let modifierText = modifierDisplayString(modifiers)
        let keyText = keyDisplayString(keyCode: keyCode)
        guard !modifierText.isEmpty else { return keyText }
        return "\(modifierText) \(keyText)"
    }

    private static func modifierDisplayString(_ modifiers: UInt32) -> String {
        var display = ""
        if modifiers & UInt32(controlKey) != 0 {
            display += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            display += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            display += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            display += "⌘"
        }
        return display
    }

    private static func keyDisplayString(keyCode: UInt32) -> String {
        keyDisplayNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyDisplayNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_Command): "Command",
        UInt32(kVK_Shift): "Shift",
        UInt32(kVK_CapsLock): "Caps Lock",
        UInt32(kVK_Option): "Option",
        UInt32(kVK_Control): "Control",
        UInt32(kVK_RightCommand): "Right Command",
        UInt32(kVK_RightShift): "Right Shift",
        UInt32(kVK_RightOption): "Right Option",
        UInt32(kVK_RightControl): "Right Control",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_UpArrow): "↑"
    ]
}

extension SettingsStore {
    var hotkeyShortcut: HotkeyShortcut {
        get {
            let shortcut = HotkeyShortcut(
                keyCode: UInt32(max(0, self[.hotkeyKeyCode])),
                modifiers: UInt32(max(0, self[.hotkeyModifiers]))
            )
            guard shortcut.validationError == nil else {
                return .defaultShortcut
            }
            return shortcut
        }
        nonmutating set {
            self[.hotkeyKeyCode] = Int(newValue.keyCode)
            self[.hotkeyModifiers] = Int(newValue.modifiers)
        }
    }
}

extension TypedSettings {
    static var hotkeyShortcut: HotkeyShortcut {
        get {
            SettingsStore.standard.hotkeyShortcut
        }
        set {
            SettingsStore.standard.hotkeyShortcut = newValue
        }
    }
}
