import XCTest
@preconcurrency import UserNotifications
@testable import Jabber

@MainActor
final class NotificationServiceTests: XCTestCase {
    /// The authorization decision is a pure mapping over `UNAuthorizationStatus`.
    /// `UNUserNotificationCenter` is a singleton that cannot be injected, so the
    /// revoked-after-granted flow is covered by a manual recipe (see the commit
    /// message); this guards the mapping that drives send-vs-notice-fallback.
    func testIsAuthorizedMapsStatuses() {
        let tests: [UNAuthorizationStatus: Bool] = [
            .authorized: true,
            .provisional: true,
            .notDetermined: false,
            .denied: false
        ]

        for (status, want) in tests {
            XCTAssertEqual(
                NotificationService.isAuthorized(status: status),
                want,
                "status \(status) should map to \(want)"
            )
        }
    }

    /// Only critical messages may block with a modal alert. Everything else
    /// posts a notification when authorized and otherwise falls back to the
    /// non-modal overlay notice, including bundle-less `swift run` binaries,
    /// which have no notification center and therefore no status.
    func testDeliveryRoutesMessages() {
        let tests: [String: (critical: Bool, status: UNAuthorizationStatus?, want: NotificationService.Delivery)] = [
            "critical when authorized": (true, .authorized, .alert),
            "critical without notification center": (true, nil, .alert),
            "authorized": (false, .authorized, .notification),
            "provisional": (false, .provisional, .notification),
            "not asked yet": (false, .notDetermined, .notice),
            "denied": (false, .denied, .notice),
            "no notification center": (false, nil, .notice)
        ]

        for (name, tc) in tests {
            XCTAssertEqual(
                NotificationService.delivery(critical: tc.critical, authorizationStatus: tc.status),
                tc.want,
                name
            )
        }
    }

    /// Feedback goes straight to the on-screen notice, synchronously and
    /// without consulting notification authorization.
    func testFeedbackAlwaysUsesTheOnScreenNotice() {
        let service = NotificationService(isValidBundle: false)
        var presented: [String] = []
        service.noticePresenter = { title, message in
            presented.append("\(title): \(message)")
        }

        service.showFeedback(title: "No Speech Detected", message: "Troy Barnes was too quiet.")

        XCTAssertEqual(presented, ["No Speech Detected: Troy Barnes was too quiet."])
    }

    func testForegroundPresentationOptionsShowBannerAndSound() {
        let options = NotificationService.foregroundPresentationOptions

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
    }
}
