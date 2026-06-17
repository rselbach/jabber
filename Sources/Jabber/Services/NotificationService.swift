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
        let logger = self.logger

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            }
            Task { @MainActor in
                guard let self else { return }
                self.isAuthorized = granted
                if !granted {
                    logger.info("User denied notification permissions, will use alert fallback")
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

    func showPermissionWarning(
        title: String,
        message: String,
        section: PermissionService.PermissionSection
    ) {
        showNotification(title: title, message: message, permissionSection: section)
    }

    func showNotification(
        title: String,
        message: String,
        permissionSection: PermissionService.PermissionSection? = nil
    ) {
        guard isValidBundle, let center = notificationCenter else {
            logger.info("Using alert fallback for notification: \(title)")
            showAlert(
                title: title,
                message: message,
                style: .informational,
                permissionSection: permissionSection
            )
            return
        }

        if isAuthorized {
            Task { @MainActor [weak self] in
                await self?.sendNotificationRequest(title: title, message: message, center: center)
            }
            return
        }

        center.getNotificationSettings { [weak self] settings in
            let authorised: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                authorised = true
            default:
                authorised = false
            }

            Task { @MainActor in
                guard let self else { return }
                self.isAuthorized = authorised
                guard authorised else {
                    self.logger.info("Notification permission not granted, using alert fallback: \(title)")
                    self.showAlert(
                        title: title,
                        message: message,
                        style: .informational,
                        permissionSection: permissionSection
                    )
                    return
                }

                await self.sendNotificationRequest(title: title, message: message, center: center)
            }
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

    private func showAlert(
        title: String,
        message: String,
        style: NSAlert.Style,
        permissionSection: PermissionService.PermissionSection? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")

        if let permissionSection {
            alert.addButton(withTitle: "Open Privacy Settings")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                PermissionService.shared.openPrivacySettings(for: permissionSection)
            }
            return
        }

        alert.runModal()
    }
}
