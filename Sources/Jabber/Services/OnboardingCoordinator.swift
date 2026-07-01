import AVFoundation
import Foundation
import os

@MainActor
@Observable
final class OnboardingCoordinator {
    enum Step: Int, CaseIterable {
        case welcome
        case microphone
        case modelDownload
        case accessibility
        case ready

        var title: String {
            switch self {
            case .welcome:
                return "Welcome"
            case .microphone:
                return "Microphone"
            case .modelDownload:
                return "Speech Model"
            case .accessibility:
                return "Accessibility"
            case .ready:
                return "Ready"
            }
        }
    }

    private(set) var step: Step = .welcome
    private(set) var microphoneStatus: AVAuthorizationStatus
    private(set) var isAccessibilityTrusted: Bool
    private(set) var didSkipAccessibility = false
    private(set) var downloadErrorMessage: String?

    private let permissionService: PermissionService
    private let modelManager: ModelManager
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "OnboardingCoordinator")
    private var permissionPollingTask: Task<Void, Never>?

    init(
        permissionService: PermissionService = .shared,
        modelManager: ModelManager = .shared
    ) {
        self.permissionService = permissionService
        self.modelManager = modelManager
        microphoneStatus = permissionService.microphoneAuthorizationStatus()
        isAccessibilityTrusted = permissionService.refreshAccessibilityPermissionStatus()
    }

    var canContinue: Bool {
        switch step {
        case .welcome:
            return true
        case .microphone:
            return microphoneStatus == .authorized
        case .modelDownload:
            return modelManager.hasAnyDownloadedModel
        case .accessibility:
            return isAccessibilityTrusted || didSkipAccessibility
        case .ready:
            return true
        }
    }

    var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return "Get Started"
        case .ready:
            return "Done"
        default:
            return "Continue"
        }
    }

    func start() {
        refreshState()
        startPermissionPolling()
    }

    func stop() {
        permissionPollingTask?.cancel()
        permissionPollingTask = nil
    }

    func continueFromCurrentStep(onComplete: () -> Void) {
        switch step {
        case .welcome:
            move(to: .microphone)
        case .microphone:
            guard canContinue else { return }
            move(to: .modelDownload)
        case .modelDownload:
            guard canContinue else { return }
            move(to: .accessibility)
        case .accessibility:
            guard canContinue else { return }
            move(to: .ready)
        case .ready:
            onComplete()
        }
    }

    func requestMicrophoneAccess() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await permissionService.requestMicrophonePermission()
            refreshState()
            if !granted {
                permissionService.openPrivacySettings(for: .microphone)
            }
        }
    }

    func openMicrophoneSettings() {
        permissionService.openPrivacySettings(for: .microphone)
        refreshState()
    }

    func openAccessibilitySettings() {
        _ = permissionService.requestAccessibilityPermission()
        permissionService.openPrivacySettings(for: .accessibility)
        refreshState()
    }

    func skipAccessibility() {
        TypedSettings[.outputMode] = TypingService.OutputMode.clipboard.rawValue
        didSkipAccessibility = true
        refreshState()
    }

    func handleModelDownloadState(_ state: ModelDownloadState) {
        guard state.modelId == AppMode.baseModelId else { return }

        switch state.phase {
        case .started, .progress, .finished:
            downloadErrorMessage = nil
        case .failed:
            guard !state.isCancelled else { return }
            downloadErrorMessage = state.errorDescription ?? state.status
        }
    }

    private func move(to nextStep: Step) {
        step = nextStep
        refreshState()

        if nextStep == .modelDownload {
            startBaseModelDownloadIfNeeded()
        }
    }

    private func refreshState() {
        microphoneStatus = permissionService.microphoneAuthorizationStatus()
        isAccessibilityTrusted = permissionService.refreshAccessibilityPermissionStatus()
        modelManager.refreshModels()
        autoAdvanceForGrantedPermission()
    }

    private func autoAdvanceForGrantedPermission() {
        switch step {
        case .microphone where microphoneStatus == .authorized:
            move(to: .modelDownload)
        case .accessibility where isAccessibilityTrusted:
            move(to: .ready)
        default:
            return
        }
    }

    private func startBaseModelDownloadIfNeeded() {
        guard !modelManager.hasAnyDownloadedModel else { return }

        if !modelManager.startDownload(AppMode.baseModelId) {
            modelManager.refreshModels()
        }
    }

    private func startPermissionPolling() {
        guard permissionPollingTask == nil else { return }

        permissionPollingTask = Task { [weak self] in
            await self?.pollPermissions()
        }
    }

    private func pollPermissions() async {
        while !Task.isCancelled {
            refreshState()

            do {
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                return
            } catch {
                logger.error("Onboarding permission polling failed: \(error.localizedDescription)")
                return
            }
        }
    }
}
