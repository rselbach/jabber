import AppKit
import os

/// What macOS does when Fn (🌐) is pressed on its own: "Press 🌐 key to" in
/// Keyboard settings. Jabber passes the key through, so with Fn as the
/// dictation hotkey anything but Do Nothing happens as well.
enum GlobeKeyAction: Equatable {
    case doNothing
    case changeInputSource
    case showEmojiAndSymbols
    case startDictation
    /// Not set, or a value this version doesn't know. What macOS does when
    /// the setting was never changed differs between Macs.
    case unknown

    private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "GlobeKeyAction")
    private static let preferencesDomain = "com.apple.HIToolbox"
    private static let usageTypeKey = "AppleFnUsageType"
    private static let keyboardSettingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    /// - Parameter usageType: `AppleFnUsageType` from `com.apple.HIToolbox`.
    init(usageType: Int?) {
        switch usageType {
        case 0:
            self = .doNothing
        case 1:
            self = .changeInputSource
        case 2:
            self = .showEmojiAndSymbols
        case 3:
            self = .startDictation
        default:
            self = .unknown
        }
    }

    /// Reads the current setting, including changes made in System Settings
    /// since the last read.
    static func current() -> GlobeKeyAction {
        if !CFPreferencesAppSynchronize(preferencesDomain as CFString) {
            logger.error("Failed to synchronize \(preferencesDomain) preferences")
        }
        let value = CFPreferencesCopyAppValue(usageTypeKey as CFString, preferencesDomain as CFString)
        return GlobeKeyAction(usageType: value as? Int)
    }

    /// Opens the Keyboard settings pane, where "Press 🌐 key to" lives.
    static func openKeyboardSettings() {
        guard let url = URL(string: keyboardSettingsURL), NSWorkspace.shared.open(url) else {
            logger.error("Failed to open Keyboard settings")
            return
        }
    }

    /// Explains what else happens when Fn is the dictation hotkey, or `nil`
    /// when the key does nothing else. Shown next to a button that opens
    /// Keyboard settings.
    var fnHotkeyWarning: String? {
        let fix = "Set “Press 🌐 key to” to Do Nothing."
        switch self {
        case .doNothing:
            return nil
        case .changeInputSource:
            return "Pressing 🌐 also switches your input source. \(fix)"
        case .showEmojiAndSymbols:
            return "Pressing 🌐 also opens Emoji & Symbols. \(fix)"
        case .startDictation:
            return "Pressing 🌐 twice also starts macOS dictation. \(fix)"
        case .unknown:
            return "If 🌐 also opens Emoji & Symbols or switches input source, set “Press 🌐 key to” to Do Nothing."
        }
    }
}
