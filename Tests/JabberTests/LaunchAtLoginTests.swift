import ServiceManagement
import XCTest
@testable import Jabber

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testStatusMapping() {
        let tests: [String: (status: SMAppService.Status, isBundled: Bool, want: LaunchAtLogin.Status)] = [
            "enabled": (.enabled, true, .enabled),
            "not registered": (.notRegistered, true, .disabled),
            "requires approval": (.requiresApproval, true, .requiresApproval),
            "never registered": (.notFound, true, .disabled),
            "bare binary": (.enabled, false, .unavailable)
        ]
        for (name, tc) in tests {
            XCTAssertEqual(LaunchAtLogin.Status(tc.status, isBundled: tc.isBundled), tc.want, name)
        }
    }

    func testToggleIsOnWhileRegistered() {
        XCTAssertTrue(LaunchAtLogin.Status.enabled.isOn)
        XCTAssertTrue(LaunchAtLogin.Status.requiresApproval.isOn)
        XCTAssertFalse(LaunchAtLogin.Status.disabled.isOn)
        XCTAssertFalse(LaunchAtLogin.Status.unavailable.isOn)
    }
}
