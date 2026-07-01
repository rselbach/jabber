import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onComplete: () -> Void
    let onAppearAction: () -> Void

    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @State private var modelManager = ModelManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(28)
        .frame(width: 520, height: 420)
        .onAppear {
            onAppearAction()
            coordinator.start()
            modelManager.refreshModels()
        }
        .onDisappear {
            coordinator.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.modelDownloadStateDidChange)) { notification in
            guard let state = notification.object as? ModelDownloadState else { return }
            coordinator.handleModelDownloadState(state)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set Up Jabber")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Step \(stepNumber) of \(OnboardingCoordinator.Step.allCases.count): \(coordinator.step.title)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.step {
        case .welcome:
            welcomeStep
        case .microphone:
            microphoneStep
        case .modelDownload:
            modelDownloadStep
        case .accessibility:
            accessibilityStep
        case .ready:
            readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber turns speech into text locally on your Mac.")
                .font(.title3)

            Text("We’ll check microphone access, install the base speech model, and optionally enable Accessibility so Jabber can type into the active app.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber needs microphone access to record dictation audio.")
                .font(.title3)

            statusLabel(
                isComplete: coordinator.microphoneStatus == .authorized,
                completeText: "Microphone access is enabled.",
                incompleteText: microphoneStatusMessage
            )

            switch coordinator.microphoneStatus {
            case .notDetermined:
                Button("Request Microphone Access") {
                    coordinator.requestMicrophoneAccess()
                }
            case .denied, .restricted:
                Button("Open System Settings") {
                    coordinator.openMicrophoneSettings()
                }
            case .authorized:
                EmptyView()
            @unknown default:
                Text("macOS returned an unknown microphone permission state.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var modelDownloadStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber uses a local speech model. The base model is required before you can dictate.")
                .font(.title3)

            if modelManager.hasAnyDownloadedModel {
                statusLabel(
                    isComplete: true,
                    completeText: "A speech model is installed.",
                    incompleteText: ""
                )
            } else {
                Text(baseModelDownloadStatus)
                    .foregroundStyle(.secondary)

                ProgressView(value: baseModelProgress)
                    .progressViewStyle(.linear)

                Text("\(Int(baseModelProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let downloadErrorMessage = coordinator.downloadErrorMessage {
                Text("Download failed: \(downloadErrorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry Download") {
                    _ = modelManager.startDownload(AppMode.baseModelId)
                }
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accessibility lets Jabber type transcriptions into the app you were using.")
                .font(.title3)

            statusLabel(
                isComplete: coordinator.isAccessibilityTrusted || coordinator.didSkipAccessibility,
                completeText: accessibilityCompleteText,
                incompleteText: "Accessibility permission is not enabled yet. You can skip this and use clipboard-only output."
            )

            if !coordinator.isAccessibilityTrusted {
                HStack(spacing: 12) {
                    Button("Open System Settings") {
                        coordinator.openAccessibilitySettings()
                    }

                    Button("Skip") {
                        coordinator.skipAccessibility()
                    }
                }
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber is ready.")
                .font(.title3)

            HStack {
                Text("Dictation hotkey")
                Spacer()
                Text(hotkeyDisplay)
                    .font(.body.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("You can change the hotkey, output mode, and model later in Settings.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(coordinator.primaryButtonTitle) {
                coordinator.continueFromCurrentStep(onComplete: onComplete)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!coordinator.canContinue)
        }
    }

    private func statusLabel(
        isComplete: Bool,
        completeText: String,
        incompleteText: String
    ) -> some View {
        Label(
            isComplete ? completeText : incompleteText,
            systemImage: isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(isComplete ? .green : .orange)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stepNumber: Int {
        coordinator.step.rawValue + 1
    }

    private var microphoneStatusMessage: String {
        switch coordinator.microphoneStatus {
        case .notDetermined:
            return "Microphone permission has not been requested yet."
        case .denied:
            return "Microphone access is denied. Open System Settings to enable it."
        case .restricted:
            return "Microphone access is restricted on this Mac."
        case .authorized:
            return "Microphone access is enabled."
        @unknown default:
            return "Microphone permission is in an unknown state."
        }
    }

    private var accessibilityCompleteText: String {
        if coordinator.isAccessibilityTrusted {
            return "Accessibility permission is enabled."
        }
        return "Jabber will copy transcriptions to the clipboard only."
    }

    private var baseModel: ModelManager.Model? {
        modelManager.models.first { $0.id == AppMode.baseModelId }
    }

    private var baseModelProgress: Double {
        guard let baseModel else { return 0 }
        return min(max(baseModel.downloadProgress, 0), 1)
    }

    private var baseModelDownloadStatus: String {
        guard let baseModel else { return "Preparing model download..." }
        if baseModel.isDownloading {
            return "Downloading \(baseModel.name)..."
        }
        return "Starting \(baseModel.name) download..."
    }

    private var hotkeyDisplay: String {
        HotkeyShortcut(
            keyCode: UInt32(max(0, hotkeyKeyCode)),
            modifiers: UInt32(max(0, hotkeyModifiers))
        ).displayString
    }
}

#Preview {
    OnboardingView(coordinator: OnboardingCoordinator(), onComplete: {}, onAppearAction: {})
}
