import AppKit
@preconcurrency import UserNotifications
import os

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "NotificationService")
    private let notificationCenter: UNUserNotificationCenter?
    private let isValidBundle: Bool
    private var isAuthorized = false

    private init() {
        isValidBundle = Bundle.main.bundleIdentifier != nil

        if isValidBundle {
            // Initialize notification center immediately
            notificationCenter = UNUserNotificationCenter.current()
            setupNotifications()
        } else {
            notificationCenter = nil
            logger.info("Running without proper bundle - notifications will use alerts")
        }
    }

    private func setupNotifications() {
        guard let center = notificationCenter else { return }

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                self?.logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            }
            Task { @MainActor in
                self?.isAuthorized = granted
                if !granted {
                    self?.logger.info("User denied notification permissions, will use alert fallback")
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
