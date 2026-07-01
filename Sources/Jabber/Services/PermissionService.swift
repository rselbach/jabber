import AVFoundation
@preconcurrency import ApplicationServices
import AppKit
import Foundation
import os

@MainActor
final class PermissionService {
    static let shared = PermissionService()

    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "PermissionService")
    private let microphonePermissionStatusCache: TimeInterval = 2.0
    private let accessibilityPermissionStatusCache: TimeInterval = 2.0
    private var lastMicrophoneStatusCheck: Date = .distantPast
    private var lastMicrophonePermissionResult: Bool = false
    private var lastAccessibilityStatusCheck: Date = .distantPast
    private var lastAccessibilityPermissionResult: Bool = false

    enum PermissionSection: String {
        case microphone = "Microphone"
        case accessibility = "Accessibility"
    }

    func requestMicrophonePermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch currentStatus {
        case .authorized:
            cacheMicrophonePermission(true)
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            cacheMicrophonePermission(granted)
            return granted
        case .denied, .restricted:
            cacheMicrophonePermission(false)
            return false
        @unknown default:
            logger.warning("Unknown microphone authorization status")
            cacheMicrophonePermission(false)
            return false
        }
    }

    func hasMicrophonePermission() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastMicrophoneStatusCheck) < microphonePermissionStatusCache {
            return lastMicrophonePermissionResult
        }

        return microphoneAuthorizationStatus(checkedAt: now) == .authorized
    }

    func microphoneAuthorizationStatus(checkedAt date: Date = Date()) -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        cacheMicrophonePermission(status == .authorized, checkedAt: date)
        return status
    }

    private func cacheMicrophonePermission(
        _ isAuthorized: Bool,
        checkedAt date: Date = Date()
    ) {
        lastMicrophoneStatusCheck = date
        lastMicrophonePermissionResult = isAuthorized
    }

    func requestAccessibilityPermission() -> Bool {
        let trusted = refreshAccessibilityPermissionStatus()
        guard !trusted else { return true }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return refreshAccessibilityPermissionStatus()
    }

    func hasAccessibilityPermission() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastAccessibilityStatusCheck) < accessibilityPermissionStatusCache {
            return lastAccessibilityPermissionResult
        }

        return refreshAccessibilityPermissionStatus(checkedAt: now)
    }

    func refreshAccessibilityPermissionStatus(checkedAt date: Date = Date()) -> Bool {
        let isTrusted = AXIsProcessTrusted()
        lastAccessibilityStatusCheck = date
        lastAccessibilityPermissionResult = isTrusted
        return isTrusted
    }

    func openPrivacySettings(for section: PermissionSection) {
        let targeted = "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section.rawValue)"
        let fallback = "x-apple.systempreferences:com.apple.preference.security?Privacy"

        for urlString in [targeted, fallback] {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                logger.info("Opened privacy settings for \(section.rawValue)")
                return
            }
        }

        logger.error("Failed to open privacy settings for \(section.rawValue)")
    }
}
