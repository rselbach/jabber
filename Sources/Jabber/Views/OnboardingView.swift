import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @Bindable var coordinator: OnboardingCoordinator
    let onComplete: () -> Void
    let onAppearAction: () -> Void

    @AppStorage(AppSettingKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyShortcut.defaultShortcut.keyCode)
    @AppStorage(AppSettingKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyShortcut.defaultShortcut.modifiers)
    @State private var modelManager = ModelManager.shared
    @State private var showAllLanguages = false
    @State private var languageSearchText = ""

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
        case .language:
            languageStep
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

            Text("We'll check microphone access, pick a language and speech model, and optionally enable Accessibility so Jabber can type into the active app.")
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

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What language will you speak most?")
                .font(.title3)

            Text("We'll show the best speech models for it.")
                .foregroundStyle(.secondary)

            ScrollView {
                if languageSearchText.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(popularLanguages, id: \.code) { lang in
                            languageCard(name: lang.name, code: lang.code)
                        }
                    }

                    if showAllLanguages {
                        Divider().padding(.vertical, 8)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(allLanguages, id: \.code) { lang in
                                languageCard(name: lang.name, code: lang.code)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(searchedLanguages, id: \.code) { lang in
                            languageCard(name: lang.name, code: lang.code)
                        }
                    }
                }
            }

            HStack {
                TextField("Search languages...", text: $languageSearchText)
                    .textFieldStyle(.roundedBorder)

                Button(showAllLanguages ? "Show Less" : "Show All") {
                    withAnimation { showAllLanguages.toggle() }
                }
            }
        }
    }

    private func languageCard(name: String, code: String) -> some View {
        let isSelected = coordinator.onboardingSelectedLanguage == code
        return Button {
            coordinator.selectLanguage(code)
        } label: {
            VStack(spacing: 4) {
                Text(name)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(code.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var modelDownloadStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your speech model")
                .font(.title3)

            Text("Recommended for \(selectedLanguageName). You can change this later in Settings.")
                .foregroundStyle(.secondary)

            ForEach(coordinator.compatibleModelsForSelectedLanguage()) { route in
                if let model = modelManager.models.first(where: { $0.id == route.modelId }) {
                    onboardingModelRow(model: model, isRecommended: route.isRecommended)
                }
            }

            if let downloadErrorMessage = coordinator.downloadErrorMessage {
                Text("Download failed: \(downloadErrorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func onboardingModelRow(model: ModelManager.Model, isRecommended: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(.semibold)

                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if model.isDownloaded {
                        Text(isBuiltIn(model) ? "Built-in" : "Downloaded")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(model.sizeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
            } else if model.isDownloaded {
                if TypedSettings[.selectedModel] == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Activate") {
                        if modelManager.selectModel(model.id) {
                            TypedSettings[.selectedModel] = model.id
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Download") {
                    _ = modelManager.startDownload(model.id)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func isBuiltIn(_ model: ModelManager.Model) -> Bool {
        AppMode.modelDefinition(for: model.id)?.isBuiltIn ?? false
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

            Text("You can change the hotkey, output mode, language, and model later in Settings.")
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

    private var popularLanguages: [(name: String, code: String)] {
        LanguageModelCatalog.popularLanguages()
    }

    private var allLanguages: [(name: String, code: String)] {
        LanguageModelCatalog.allLanguages()
    }

    private var searchedLanguages: [(name: String, code: String)] {
        let query = languageSearchText.lowercased()
        return allLanguages.filter {
            $0.name.lowercased().contains(query) || $0.code.lowercased().contains(query)
        }
    }

    private var selectedLanguageName: String {
        let code = coordinator.onboardingSelectedLanguage
        if code == "auto" { return "auto-detect" }
        return Constants.sortedLanguages.first { $0.code == code }?.name ?? code
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
