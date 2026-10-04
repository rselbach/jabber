import AVFoundation

/// What the General page shows for one permission: whether it is granted, a
/// line on what it is for, and the button that fixes it.
struct PermissionStatus: Equatable {
    enum Action: Equatable {
        case none
        case requestAccess
        case openSettings
    }

    let isGranted: Bool
    /// Missing while something the user turned on depends on it.
    let needsAttention: Bool
    let detail: String
    let action: Action

    static func microphone(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:
            return PermissionStatus(
                isGranted: true,
                needsAttention: false,
                detail: "Jabber can hear you while you dictate.",
                action: .none
            )
        case .notDetermined:
            return PermissionStatus(
                isGranted: false,
                needsAttention: true,
                detail: "Dictation needs it to record.",
                action: .requestAccess
            )
        case .restricted:
            return PermissionStatus(
                isGranted: false,
                needsAttention: true,
                detail: "Restricted on this Mac, so Jabber can't record.",
                action: .none
            )
        case .denied:
            return deniedMicrophone
        @unknown default:
            return deniedMicrophone
        }
    }

    /// - Parameter isNeeded: Typing into apps or a lone-key hotkey is turned on.
    static func accessibility(isTrusted: Bool, isNeeded: Bool) -> PermissionStatus {
        if isTrusted {
            return PermissionStatus(
                isGranted: true,
                needsAttention: false,
                detail: "Jabber can type into apps and use lone-key hotkeys like Right Option.",
                action: .none
            )
        }
        if isNeeded {
            return PermissionStatus(
                isGranted: false,
                needsAttention: true,
                detail: "Needed to type into apps and for lone-key hotkeys like Right Option.",
                action: .openSettings
            )
        }
        return PermissionStatus(
            isGranted: false,
            needsAttention: false,
            detail: "Only needed to type into apps or for lone-key hotkeys like Right Option.",
            action: .openSettings
        )
    }

    private static let deniedMicrophone = PermissionStatus(
        isGranted: false,
        needsAttention: true,
        detail: "Turned off, so Jabber can't record.",
        action: .openSettings
    )
}
