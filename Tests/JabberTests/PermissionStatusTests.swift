import AVFoundation
import XCTest
@testable import Jabber

final class PermissionStatusTests: XCTestCase {
    func testMicrophone() {
        let tests: [String: (
            status: AVAuthorizationStatus,
            wantGranted: Bool,
            wantAttention: Bool,
            wantAction: PermissionStatus.Action
        )] = [
            "granted": (.authorized, true, false, .none),
            "never asked": (.notDetermined, false, true, .requestAccess),
            "denied": (.denied, false, true, .openSettings),
            "restricted by the Mac": (.restricted, false, true, .none)
        ]

        for (name, tc) in tests {
            let got = PermissionStatus.microphone(tc.status)
            XCTAssertEqual(got.isGranted, tc.wantGranted, name)
            XCTAssertEqual(got.needsAttention, tc.wantAttention, name)
            XCTAssertEqual(got.action, tc.wantAction, name)
        }
    }

    func testAccessibility() {
        let tests: [String: (
            isTrusted: Bool,
            isNeeded: Bool,
            wantGranted: Bool,
            wantAttention: Bool,
            wantAction: PermissionStatus.Action
        )] = [
            "granted": (true, true, true, false, .none),
            "granted but unused": (true, false, true, false, .none),
            "missing while typing into apps": (false, true, false, true, .openSettings),
            "missing in clipboard mode": (false, false, false, false, .openSettings)
        ]

        for (name, tc) in tests {
            let got = PermissionStatus.accessibility(isTrusted: tc.isTrusted, isNeeded: tc.isNeeded)
            XCTAssertEqual(got.isGranted, tc.wantGranted, name)
            XCTAssertEqual(got.needsAttention, tc.wantAttention, name)
            XCTAssertEqual(got.action, tc.wantAction, name)
        }
    }
}
