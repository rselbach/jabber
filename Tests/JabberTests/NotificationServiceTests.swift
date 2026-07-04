import XCTest
@preconcurrency import UserNotifications
@testable import Jabber

@MainActor
final class NotificationServiceTests: XCTestCase {
    /// The authorization decision is a pure mapping over `UNAuthorizationStatus`.
    /// `UNUserNotificationCenter` is a singleton that cannot be injected, so the
    /// revoked-after-granted flow is covered by a manual recipe (see the commit
    /// message); this guards the mapping that drives send-vs-alert-fallback.
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

    func testForegroundPresentationOptionsShowBannerAndSound() {
        let options = NotificationService.foregroundPresentationOptions

        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
    }
}
