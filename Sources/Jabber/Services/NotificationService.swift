import AppKit
@preconcurrency import UserNotifications
import os

@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()
    nonisolated static let foregroundPresentationOptions: UNNotificationPresentationOptions = [.banner, .sound]

    /// How a message reaches the user.
    enum Delivery: Equatable {
        /// Modal `NSAlert`, reserved for critical messages.
        case alert
        /// System notification through `UNUserNotificationCenter`.
        case notification
        /// Transient on-screen notice through `noticePresenter`.
        case notice
    }

    /// Shows feedback, and messages that cannot be posted as system
    /// notifications, without blocking the user. AppDelegate points this at
    /// the recording overlay so the service stays free of window management.
    var noticePresenter: ((_ title: String, _ message: String) -> Void)?

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "NotificationService")
    private let notificationCenter: UNUserNotificationCenter?

    /// `isValidBundle` is false for bundle-less binaries such as bare
    /// `swift run`, and in tests, which must not touch the
    /// `UNUserNotificationCenter` singleton.
    init(isValidBundle: Bool = Bundle.main.bundleIdentifier != nil) {
        if isValidBundle {
            notificationCenter = UNUserNotificationCenter.current()
        } else {
            notificationCenter = nil
        }

        super.init()

        if isValidBundle {
            notificationCenter?.delegate = self
        } else {
            logger.info("Running without proper bundle - notifications will use on-screen notices")
        }
    }

    /// Asks for permission to post notifications. Only the first request
    /// prompts; once the user has answered, the system returns the recorded
    /// choice without showing anything. AppDelegate holds this back until
    /// onboarding is out of the way so the prompt never covers the welcome
    /// screen.
    func requestAuthorization() {
        guard let center = notificationCenter else { return }
        let logger = self.logger

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            }
            if !granted {
                logger.info("Notification permission not granted, will use on-screen notices")
            }
        }
    }

    func showError(title: String, message: String, critical: Bool = false) {
        deliver(title: title, message: message, critical: critical)
    }

    func showWarning(title: String, message: String) {
        deliver(title: title, message: message, critical: false)
    }

    /// Feedback on something the user just did, such as a hotkey press or a
    /// dictation that just ended. Always the on-screen notice: the user is
    /// looking at the overlay, and a system notification would sit in
    /// Notification Center long after it stopped mattering.
    func showFeedback(title: String, message: String) {
        presentNotice(title: title, message: message)
    }

    private func deliver(title: String, message: String, critical: Bool) {
        let center = notificationCenter

        // Recheck authorization on every send. The user can revoke notification
        // permission in System Settings after initially granting it, in which
        // case `center.add` still succeeds but the system never displays the
        // notification and all non-critical warnings vanish silently. Reading
        // the current settings is async and cheap, so re-verify per send and
        // fall back to the on-screen notice when revoked. Bundle-less binaries
        // have no center and never touch `UNUserNotificationCenter`.
        Task { @MainActor [weak self] in
            let status = await center?.notificationSettings().authorizationStatus
            guard let self else { return }

            switch Self.delivery(critical: critical, authorizationStatus: status) {
            case .alert:
                self.showAlert(title: title, message: message)
            case .notification:
                // A non-nil status implies a center.
                guard let center else { return }
                await self.sendNotificationRequest(title: title, message: message, center: center)
            case .notice:
                self.presentNotice(title: title, message: message)
            }
        }
    }

    /// Picks how a message reaches the user. Pure so the routing is testable
    /// without the `UNUserNotificationCenter` singleton. Only critical
    /// messages block with a modal alert; everything else posts a
    /// notification when authorized and otherwise shows the non-modal notice.
    /// `authorizationStatus` is nil when there is no notification center,
    /// which is the case for bundle-less binaries such as bare `swift run`.
    static func delivery(critical: Bool, authorizationStatus: UNAuthorizationStatus?) -> Delivery {
        if critical {
            return .alert
        }
        guard let authorizationStatus, isAuthorized(status: authorizationStatus) else { return .notice }
        return .notification
    }

    /// Maps a `UNAuthorizationStatus` to whether Jabber may post. Pure so the
    /// authorization decision is testable without the `UNUserNotificationCenter`
    /// singleton (which cannot be injected).
    static func isAuthorized(status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func sendNotificationRequest(
        title: String,
        message: String,
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to show notification: \(error.localizedDescription)")
        }
    }

    private func presentNotice(title: String, message: String) {
        guard let noticePresenter else {
            logger.error("No on-screen notice presenter, dropping message: \(title)")
            return
        }
        logger.info("Showing on-screen notice: \(title)")
        noticePresenter(title, message)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentationOptions
    }
}
