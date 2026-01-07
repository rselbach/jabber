import AppKit
@preconcurrency import UserNotifications
import os

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "NotificationService")
    private var notificationCenter: UNUserNotificationCenter?
    private let isValidBundle: Bool

    private init() {
        isValidBundle = Bundle.main.bundleIdentifier != nil

        if isValidBundle {
            setupNotifications()
        } else {
            logger.info("Running without proper bundle - notifications will use alerts")
        }
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                self.logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            }
            if granted {
                Task { @MainActor in
                    self.notificationCenter = center
                }
            }
        }
    }

    func showError(title: String, message: String, critical: Bool = false) {
        if critical {
            showAlert(title: title, message: message, style: .critical)
        } else {
            showNotification(title: title, message: message)
        }
    }

    func showWarning(title: String, message: String) {
        showNotification(title: title, message: message)
    }

    func showNotification(title: String, message: String) {
        guard isValidBundle, let center = notificationCenter else {
            logger.info("Using alert fallback for notification: \(title)")
            showAlert(title: title, message: message, style: .informational)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                self.logger.error("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
