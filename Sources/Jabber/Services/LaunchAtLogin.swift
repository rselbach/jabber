import Foundation
import ServiceManagement

/// Launch at Login, backed by the macOS login item list rather than a stored
/// setting, so the toggle always shows what macOS will actually do.
@MainActor
enum LaunchAtLogin {
    enum Status: Equatable {
        case enabled
        case disabled
        /// Registered, but the user switched it off in Login Items.
        case requiresApproval
        /// A bare `swift run` binary has no bundle to register.
        case unavailable

        init(_ status: SMAppService.Status, isBundled: Bool) {
            guard isBundled else {
                self = .unavailable
                return
            }
            switch status {
            case .enabled:
                self = .enabled
            case .requiresApproval:
                self = .requiresApproval
            // macOS reports a main app that was never registered as not
            // found; registering it works all the same.
            case .notRegistered, .notFound:
                self = .disabled
            @unknown default:
                self = .disabled
            }
        }

        var isOn: Bool {
            self == .enabled || self == .requiresApproval
        }
    }

    static var status: Status {
        Status(SMAppService.mainApp.status, isBundled: Bundle.main.bundleIdentifier != nil)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
