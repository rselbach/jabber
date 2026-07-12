import AVFoundation
import Foundation
import os

@MainActor
@Observable
final class OnboardingCoordinator {
    enum Step: Int, CaseIterable {
        case welcome
        case language
        case permissions
        case modelDownload
        case ready

        var title: String {
            switch self {
            case .welcome:
                return "Welcome"
            case .language:
                return "Language"
            case .permissions:
                return "Permissions"
            case .modelDownload:
                return "Speech Model"
            case .ready:
                return "Ready"
            }
        }
    }

    private(set) var step: Step = .welcome
    private(set) var isNavigatingForward = true
    private(set) var microphoneStatus: AVAuthorizationStatus = .notDetermined
    private(set) var isAccessibilityTrusted = false
    private(set) var didSkipAccessibility = false
    private(set) var downloadErrorMessage: String?
    private(set) var onboardingSelectedLanguage: String
    private(set) var selectedModelId: String

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
        onboardingSelectedLanguage = TypedSettings[.selectedLanguage]
        selectedModelId = TypedSettings[.selectedModel]
    }

    var canContinue: Bool {
        switch step {
        case .welcome, .ready:
            return true
        case .language:
            return !onboardingSelectedLanguage.isEmpty
        case .permissions:
            return microphoneStatus == .authorized
                && (isAccessibilityTrusted || didSkipAccessibility)
        case .modelDownload:
            return isSelectedModelReady
        }
    }

    var canGoBack: Bool {
        step != .welcome
    }

    /// Explains why Continue is disabled so the footer never leaves the user
    /// staring at a dead button.
    var continueHint: String? {
        guard !canContinue else { return nil }

        switch step {
        case .welcome, .ready:
            return nil
        case .language:
            return "Select a language to continue"
        case .permissions:
            if microphoneStatus != .authorized {
                return "Microphone access is required for dictation"
            }
            return "Enable Accessibility or choose clipboard output"
        case .modelDownload:
            if let model = selectedModel, model.isDownloading {
                return "Downloading \(model.name) — \(Int(model.downloadProgress * 100))%"
            }
            return "Download or choose a speech model to continue"
        }
    }

    var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return "Get Started"
        case .ready:
            return "Start Dictating"
        default:
            return "Continue"
        }
    }

    var selectedModel: ModelManager.Model? {
        modelManager.models.first { $0.id == selectedModelId }
    }

    func selectLanguage(_ languageCode: String) {
        // Re-tapping the already-selected language (e.g. after going Back
        // from the model step) must not clobber a model the user picked
        // manually with the recommendation.
        guard languageCode != onboardingSelectedLanguage else { return }

        onboardingSelectedLanguage = languageCode
        TypedSettings[.selectedLanguage] = languageCode

        let recommended = LanguageModelCatalog.recommendedModelId(for: languageCode)
        selectedModelId = recommended
        TypedSettings[.selectedModel] = recommended

        modelManager.refreshModels()
    }

    func selectModel(_ modelId: String) {
        selectedModelId = modelId
        if !modelManager.selectModel(modelId) {
            // selectModel is a no-op when the model is not downloaded yet or
            // already selected; persist the choice directly in that case.
            TypedSettings[.selectedModel] = modelId
        }
    }

    func recommendedModelIdForSelectedLanguage() -> String {
        LanguageModelCatalog.recommendedModelId(for: onboardingSelectedLanguage)
    }

    func compatibleModelsForSelectedLanguage() -> [LanguageModelCatalog.Route] {
        LanguageModelCatalog.routes(for: onboardingSelectedLanguage)
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
        guard canContinue else { return }

        switch step {
        case .welcome:
            move(to: .language)
        case .language:
            // Kick off the recommended download now so it runs in the
            // background while the user deals with permission prompts.
            startRecommendedModelDownloadIfNeeded()
            move(to: .permissions)
        case .permissions:
            move(to: .modelDownload)
        case .modelDownload:
            move(to: .ready)
        case .ready:
            onComplete()
        }
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        isNavigatingForward = false
        step = previous
        refreshState()
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
        guard compatibleModelsForSelectedLanguage().contains(where: { $0.modelId == state.modelId }) else { return }

        switch state.phase {
        case .started, .progress, .finished:
            downloadErrorMessage = nil
        case .failed:
            guard !state.isCancelled else {
                downloadErrorMessage = nil
                return
            }
            downloadErrorMessage = state.errorDescription ?? state.status
        }
    }

    func cancelModelDownload(_ modelId: String) {
        downloadErrorMessage = nil
        modelManager.cancelDownload(modelId)
    }

    private var isSelectedModelReady: Bool {
        selectedModel?.isDownloaded ?? false
    }

    private func move(to nextStep: Step) {
        isNavigatingForward = true
        step = nextStep
        refreshState()
    }

    private func refreshState() {
        microphoneStatus = permissionService.microphoneAuthorizationStatus()
        isAccessibilityTrusted = permissionService.refreshAccessibilityPermissionStatus()
        modelManager.refreshModels()
    }

    private func startRecommendedModelDownloadIfNeeded() {
        let recommended = recommendedModelIdForSelectedLanguage()
        guard let model = modelManager.models.first(where: { $0.id == recommended }) else { return }
        guard !model.isDownloaded, !model.isDownloading else { return }

        if !modelManager.startDownload(recommended) {
            modelManager.refreshModels()
        }
    }

    private func startPermissionPolling() {
        guard permissionPollingTask == nil else { return }

        permissionPollingTask = Task { [weak self] in
            // Resolve self weakly per iteration so the coordinator can deinit
            // when its strong refs drop, even if stop() is never called. The
            // previous `await self?.pollPermissions()` strong-promoted self for
            // the entire (infinite) loop, leaking the coordinator and polling
            // AXIsProcessTrusted()/refreshModels() every second forever after
            // the onboarding window closed.
            while let self, !Task.isCancelled {
                guard await self.pollPermissionsOnce() else { return }
            }
        }
    }

    /// One polling iteration. Returns false (and stops the loop) on cancel or
    /// sleep failure, matching the previous `pollPermissions` semantics; true
    /// to continue.
    @discardableResult
    private func pollPermissionsOnce() async -> Bool {
        refreshState()

        do {
            try await Task.sleep(for: .seconds(1))
        } catch is CancellationError {
            return false
        } catch {
            logger.error("Onboarding permission polling failed: \(error.localizedDescription)")
            return false
        }

        return true
    }
}
