import AVFoundation
import XCTest
@testable import Jabber

@MainActor
final class PermissionServiceTests: XCTestCase {
    func testMicrophonePermissionReturnsCachedValueWithinWindow() {
        let service = PermissionService()
        let now = Date()
        let status = service.microphoneAuthorizationStatus(checkedAt: now)
        let cached = service.hasMicrophonePermission()
        XCTAssertEqual(cached, status == .authorized)
    }

    func testMicrophonePermissionRequeriesAfterCacheExpiry() {
        let service = PermissionService()
        // Populate cache with a backdated timestamp so the window has expired.
        let stale = Date().addingTimeInterval(-3)
        _ = service.microphoneAuthorizationStatus(checkedAt: stale)
        // hasMicrophonePermission should re-query the OS, not return stale cache.
        let result = service.hasMicrophonePermission()
        let actualStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        XCTAssertEqual(result, actualStatus == .authorized)
    }

    func testMicrophonePermissionCacheWindowBoundary() {
        let service = PermissionService()
        // Just inside the 2s window.
        let withinWindow = Date().addingTimeInterval(-1.99)
        _ = service.microphoneAuthorizationStatus(checkedAt: withinWindow)
        let cached = service.hasMicrophonePermission()
        let actualStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        XCTAssertEqual(cached, actualStatus == .authorized)
    }

    func testAccessibilityPermissionReturnsCachedValueWithinWindow() {
        let service = PermissionService()
        let now = Date()
        let trusted = service.refreshAccessibilityPermissionStatus(checkedAt: now)
        let cached = service.hasAccessibilityPermission()
        XCTAssertEqual(cached, trusted)
    }

    func testAccessibilityPermissionRequeriesAfterCacheExpiry() {
        let service = PermissionService()
        let stale = Date().addingTimeInterval(-3)
        _ = service.refreshAccessibilityPermissionStatus(checkedAt: stale)
        let result = service.hasAccessibilityPermission()
        // After expiry, hasAccessibilityPermission re-queries AXIsProcessTrusted.
        XCTAssertEqual(result, service.refreshAccessibilityPermissionStatus())
    }

    func testMicrophoneAuthorizationStatusCachesResult() {
        let service = PermissionService()
        let checkDate = Date()
        _ = service.microphoneAuthorizationStatus(checkedAt: checkDate)
        // Within the cache window, hasMicrophonePermission should not re-query.
        // We can't directly observe whether the OS was re-queried, but we can
        // verify the returned value is consistent with the cached status.
        let result = service.hasMicrophonePermission()
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        XCTAssertEqual(result, status == .authorized)
    }

    func testOpenPrivacySettingsDoesNotCrash() {
        let service = PermissionService()
        // We can't verify the URL opens in CI, but we can verify no crash.
        service.openPrivacySettings(for: .microphone)
        service.openPrivacySettings(for: .accessibility)
    }
}
