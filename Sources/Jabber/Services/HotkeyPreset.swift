import Carbon
import Foundation

/// The hotkeys onboarding offers as one-click choices. Any other shortcut is
/// a custom one, recorded with `HotkeyRecorderView`.
enum HotkeyPreset: CaseIterable, Identifiable {
    case optionSpace
    case rightOption
    case fn

    var id: Self {
        self
    }

    var shortcut: HotkeyShortcut {
        switch self {
        case .optionSpace:
            return .defaultShortcut
        case .rightOption:
            return HotkeyShortcut(keyCode: UInt32(kVK_RightOption), modifiers: 0)
        case .fn:
            return HotkeyShortcut(keyCode: UInt32(kVK_Function), modifiers: 0)
        }
    }

    var detail: String {
        switch self {
        case .optionSpace:
            return "Works without Typing Access. Alfred, Raycast, and ChatGPT default to it too."
        case .rightOption:
            return "The Option key right of the space bar. Left Option works as usual."
        case .fn:
            return "The fn or 🌐 key. Some third-party keyboards don't send it."
        }
    }

    init?(shortcut: HotkeyShortcut) {
        guard let preset = Self.allCases.first(where: { $0.shortcut == shortcut }) else {
            return nil
        }
        self = preset
    }
}
