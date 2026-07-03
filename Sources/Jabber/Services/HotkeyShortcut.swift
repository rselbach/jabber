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
                return "Shortcut must include Command, Control, or Option — or use a lone modifier like Right Option."
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

    /// Individual labels for rendering the shortcut as separate keycaps:
    /// ⌃⌥ Space → ["⌃", "⌥", "Space"], Right Option → ["Right Option"].
    var keycapLabels: [String] {
        let modifierGlyphs = Self.modifierDisplayString(modifiers).map(String.init)
        return modifierGlyphs + [Self.keyDisplayString(keyCode: keyCode)]
    }

    var validationError: ValidationError? {
        Self.validationError(keyCode: keyCode, modifiers: modifiers)
    }

    /// Key codes that represent a standalone modifier key. Carbon's
    /// `RegisterEventHotKey` cannot register these on their own (a bare modifier
    /// produces no key-down event, and Carbon modifier flags do not encode the
    /// physical side), so modifier-only shortcuts take a separate runtime path.
    static let modifierOnlyKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand),
        UInt32(kVK_Shift), UInt32(kVK_RightShift),
        UInt32(kVK_Option), UInt32(kVK_RightOption),
        UInt32(kVK_Control), UInt32(kVK_RightControl)
    ]

    /// `true` when the shortcut is a single modifier key pressed on its own
    /// (e.g. Right Option), with no additional modifiers.
    var isModifierOnly: Bool {
        modifiers == 0 && Self.modifierOnlyKeyCodes.contains(keyCode)
    }

    /// Maps a modifier key code to its Carbon modifier flag, or `nil` when the
    /// code is not a standalone modifier key.
    static func carbonModifier(forKeyCode keyCode: UInt32) -> UInt32? {
        switch keyCode {
        case UInt32(kVK_Command), UInt32(kVK_RightCommand):
            return UInt32(cmdKey)
        case UInt32(kVK_Shift), UInt32(kVK_RightShift):
            return UInt32(shiftKey)
        case UInt32(kVK_Option), UInt32(kVK_RightOption):
            return UInt32(optionKey)
        case UInt32(kVK_Control), UInt32(kVK_RightControl):
            return UInt32(controlKey)
        default:
            return nil
        }
    }

    /// Maps a modifier key code to the cumulative `CGEventFlags` mask for its
    /// family (both physical sides of a modifier share one flag — e.g. Left and
    /// Right Option both report `.maskAlternate`). Returns `nil` for codes that
    /// are not a standalone modifier key.
    ///
    /// Used by the modifier-only event tap to read a flag transition's direction
    /// from the event itself rather than `CGEventSource.keyState`, which lags
    /// inside a `.defaultTap` callback (it still reflects pre-transition state).
    static func cgEventFlag(forKeyCode keyCode: UInt32) -> CGEventFlags? {
        switch keyCode {
        case UInt32(kVK_Command), UInt32(kVK_RightCommand):
            return .maskCommand
        case UInt32(kVK_Shift), UInt32(kVK_RightShift):
            return .maskShift
        case UInt32(kVK_Option), UInt32(kVK_RightOption):
            return .maskAlternate
        case UInt32(kVK_Control), UInt32(kVK_RightControl):
            return .maskControl
        default:
            return nil
        }
    }

    static func validationError(
        keyCode: UInt32,
        modifiers: UInt32
    ) -> ValidationError? {
        if keyCode == UInt32(kVK_Escape) {
            return .escapeKey
        }

        // A bare modifier key (e.g. Right Option) is a valid shortcut on its own
        // and needs no additional required modifier.
        if modifiers == 0, modifierOnlyKeyCodes.contains(keyCode) {
            return nil
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

enum HotkeyActivationMode: String, CaseIterable, Sendable {
    case hold
    case toggle
    case automatic

    static let defaultMode = HotkeyActivationMode.hold

    var displayName: String {
        switch self {
        case .hold:
            return "Hold"
        case .toggle:
            return "Toggle"
        case .automatic:
            return "Automatic"
        }
    }

    var description: String {
        switch self {
        case .hold:
            return "Press and hold to record, release to stop."
        case .toggle:
            return "Tap once to start recording, tap again to stop."
        case .automatic:
            return "Quick tap toggles recording; holding behaves like push-to-talk."
        }
    }
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

    var hotkeyActivationMode: HotkeyActivationMode {
        get {
            HotkeyActivationMode(rawValue: self[.hotkeyActivationMode]) ?? .defaultMode
        }
        nonmutating set {
            self[.hotkeyActivationMode] = newValue.rawValue
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

    static var hotkeyActivationMode: HotkeyActivationMode {
        get {
            SettingsStore.standard.hotkeyActivationMode
        }
        set {
            SettingsStore.standard.hotkeyActivationMode = newValue
        }
    }

    /// Currently selected refinement provider. Read at call time by the router;
    /// changing this does NOT rebuild the DictationCoordinator.
    static var postProcessingProviderKind: PostProcessingProviderKind {
        get {
            PostProcessingProviderKind(rawValue: SettingsStore.standard[.postProcessingProviderKind]) ?? .defaultValue
        }
        set {
            SettingsStore.standard[.postProcessingProviderKind] = newValue.rawValue
        }
    }

    /// Currently selected OpenRouter model slug (always validated against the
    /// static catalog on read).
    static var openRouterModel: String {
        get {
            SettingsStore.standard[.openRouterModel]
        }
        set {
            SettingsStore.standard[.openRouterModel] = newValue
        }
    }
}
