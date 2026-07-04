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
    @State private var showOtherModels = false
    @State private var languageSearchText = ""
    @State private var tryItText = ""

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.top, 24)
                .padding(.horizontal, 180)
                .opacity(coordinator.step == .welcome ? 0 : 1)

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .id(coordinator.step)
                .transition(stepTransition)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 720, height: 560)
        .background(backgroundView)
        .animation(.spring(duration: 0.35), value: coordinator.step)
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

    // MARK: - Chrome

    private var backgroundView: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .init(x: 0.5, y: 0.05),
                startRadius: 0,
                endRadius: 420
            )

            RadialGradient(
                colors: [Color.accentColor.opacity(0.05), .clear],
                center: .init(x: 0.15, y: 1.0),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(progressSteps, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= coordinator.step.rawValue ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.step)
    }

    private var progressSteps: [OnboardingCoordinator.Step] {
        OnboardingCoordinator.Step.allCases.filter { $0 != .welcome }
    }

    private var stepTransition: AnyTransition {
        let entering: Edge = coordinator.isNavigatingForward ? .trailing : .leading
        let leaving: Edge = coordinator.isNavigatingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: entering).combined(with: .opacity),
            removal: .move(edge: leaving).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.step {
        case .welcome:
            welcomeStep
        case .language:
            languageStep
        case .permissions:
            permissionsStep
        case .modelDownload:
            modelDownloadStep
        case .ready:
            readyStep
        }
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .shadow(color: .accentColor.opacity(0.35), radius: 10)
                .padding(.bottom, 4)

            Text(title)
                .font(.system(size: 26, weight: .bold))

            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                coordinator.goBack()
            }
            .controlSize(.large)
            .opacity(coordinator.canGoBack ? 1 : 0)
            .disabled(!coordinator.canGoBack)

            Spacer()

            if let hint = coordinator.continueHint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button(coordinator.primaryButtonTitle) {
                coordinator.continueFromCurrentStep(onComplete: onComplete)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!coordinator.canContinue)
        }
    }

    private func card(_ content: some View) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quinary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: 130, height: 130)
                    .blur(radius: 40)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 110, height: 110)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            }
            .padding(.bottom, 20)

            Text("Speak. Jabber types.")
                .font(.system(size: 34, weight: .bold))

            Text("Fast, private dictation that works in every app.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            HStack(spacing: 16) {
                featureCard(
                    symbol: "lock.shield.fill",
                    title: "Private",
                    detail: "Everything runs on your Mac. Audio never leaves it."
                )
                featureCard(
                    symbol: "bolt.fill",
                    title: "Fast",
                    detail: "Local speech models tuned for Apple silicon."
                )
                featureCard(
                    symbol: "keyboard.fill",
                    title: "Everywhere",
                    detail: "Press a hotkey and dictate into any app."
                )
            }
            .padding(.top, 36)

            Spacer()
        }
    }

    private func featureCard(symbol: String, title: String, detail: String) -> some View {
        card(
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 28)

                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 170)
        )
    }

    // MARK: - Language

    private var languageStep: some View {
        VStack(spacing: 16) {
            stepHeader(
                title: "What language will you speak?",
                subtitle: "Jabber recommends the best speech model for it."
            )

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search languages", text: $languageSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quinary)
                )

                if languageSearchText.isEmpty {
                    Button(showAllLanguages ? "Popular Only" : "Show All") {
                        withAnimation { showAllLanguages.toggle() }
                    }
                }
            }
            .frame(maxWidth: 460)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(displayedLanguages, id: \.code) { lang in
                        languageCard(name: lang.name, code: lang.code)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: 560)
        }
        .padding(.top, 8)
    }

    private var displayedLanguages: [(name: String, code: String)] {
        if !languageSearchText.isEmpty {
            let query = languageSearchText.lowercased()
            return allLanguages.filter {
                $0.name.lowercased().contains(query) || $0.code.lowercased().contains(query)
            }
        }
        return showAllLanguages ? allLanguages : popularLanguages
    }

    private func languageCard(name: String, code: String) -> some View {
        let isSelected = coordinator.onboardingSelectedLanguage == code
        return Button {
            coordinator.selectLanguage(code)
        } label: {
            HStack(spacing: 10) {
                Text(Self.languageFlags[code] ?? "🌐")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Text(code.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private static let languageFlags: [String: String] = [
        "en": "🇺🇸", "es": "🇪🇸", "fr": "🇫🇷", "de": "🇩🇪", "pt": "🇧🇷",
        "it": "🇮🇹", "ja": "🇯🇵", "ko": "🇰🇷", "zh": "🇨🇳", "hi": "🇮🇳", "ar": "🇸🇦"
    ]

    // MARK: - Permissions

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            stepHeader(
                title: "Let Jabber listen and type",
                subtitle: "Two permissions make dictation work anywhere."
            )

            VStack(spacing: 12) {
                microphoneCard
                accessibilityCard

                if !coordinator.isAccessibilityTrusted && !coordinator.didSkipAccessibility {
                    Button("Skip — copy results to the clipboard instead") {
                        coordinator.skipAccessibility()
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: 520)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 8)
    }

    private var microphoneCard: some View {
        permissionCard(
            symbol: "mic.fill",
            symbolColor: .blue,
            title: "Microphone",
            detail: microphoneDetail,
            isGranted: coordinator.microphoneStatus == .authorized
        ) {
            switch coordinator.microphoneStatus {
            case .notDetermined:
                Button("Allow") {
                    coordinator.requestMicrophoneAccess()
                }
                .buttonStyle(.borderedProminent)
            case .denied, .restricted:
                Button("Open Settings") {
                    coordinator.openMicrophoneSettings()
                }
                .buttonStyle(.bordered)
            default:
                EmptyView()
            }
        }
    }

    private var microphoneDetail: String {
        switch coordinator.microphoneStatus {
        case .authorized:
            return "Jabber can hear your dictation."
        case .denied:
            return "Access denied. Enable it in System Settings to dictate."
        case .restricted:
            return "Microphone access is restricted on this Mac."
        default:
            return "Jabber listens only while you hold the hotkey."
        }
    }

    private var accessibilityCard: some View {
        permissionCard(
            symbol: "keyboard.fill",
            symbolColor: .purple,
            title: "Typing Access",
            detail: accessibilityDetail,
            isGranted: coordinator.isAccessibilityTrusted,
            skippedNote: coordinator.didSkipAccessibility && !coordinator.isAccessibilityTrusted ? "Clipboard mode" : nil
        ) {
            if !coordinator.isAccessibilityTrusted {
                Button("Open Settings") {
                    coordinator.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var accessibilityDetail: String {
        if coordinator.isAccessibilityTrusted {
            return "Jabber can type into the app you're using."
        }
        if coordinator.didSkipAccessibility {
            return "Transcriptions will be copied to the clipboard."
        }
        return "Lets Jabber place text directly into the app you're using."
    }

    private func permissionCard(
        symbol: String,
        symbolColor: Color,
        title: String,
        detail: String,
        isGranted: Bool,
        skippedNote: String? = nil,
        @ViewBuilder action: () -> some View
    ) -> some View {
        card(
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(symbolColor.gradient)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isGranted {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if let skippedNote {
                    Text(skippedNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                action()
            }
            .padding(16)
        )
        .animation(.spring(duration: 0.3), value: isGranted)
    }

    // MARK: - Speech model

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            stepHeader(
                title: "Choose your speech model",
                subtitle: "Recommended for \(selectedLanguageName). You can switch anytime in Settings."
            )

            ScrollView {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(primaryModelRoutes) { route in
                            if let model = model(for: route.modelId) {
                                modelCard(model: model, isRecommended: route.isRecommended)
                            }
                        }
                    }

                    if !secondaryModelRoutes.isEmpty {
                        Button {
                            withAnimation { showOtherModels.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(showOtherModels ? "Hide other models" : "Show other models")
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .rotationEffect(.degrees(showOtherModels ? 180 : 0))
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if showOtherModels {
                            VStack(spacing: 8) {
                                ForEach(secondaryModelRoutes) { route in
                                    if let model = model(for: route.modelId) {
                                        compactModelRow(model: model)
                                    }
                                }
                            }
                        }
                    }

                    if let downloadErrorMessage = coordinator.downloadErrorMessage {
                        Label("Download failed: \(downloadErrorMessage)", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
    }

    /// Recommended and built-in models get full cards; the rest are tucked
    /// behind a disclosure so first-run users are not staring at a wall of
    /// quantization variants.
    private var primaryModelRoutes: [LanguageModelCatalog.Route] {
        coordinator.compatibleModelsForSelectedLanguage().filter {
            $0.isRecommended || isBuiltIn(modelId: $0.modelId)
        }
    }

    private var secondaryModelRoutes: [LanguageModelCatalog.Route] {
        coordinator.compatibleModelsForSelectedLanguage().filter {
            !$0.isRecommended && !isBuiltIn(modelId: $0.modelId)
        }
    }

    private func model(for modelId: String) -> ModelManager.Model? {
        modelManager.models.first { $0.id == modelId }
    }

    private func modelCard(model: ModelManager.Model, isRecommended: Bool) -> some View {
        let isActive = coordinator.selectedModelId == model.id
        return card(
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(model.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

                HStack {
                    Label(model.sizeHint, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                modelAction(model: model, isActive: isActive)
            }
            .padding(16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func modelAction(model: ModelManager.Model, isActive: Bool) -> some View {
        if model.isDownloading {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: model.downloadProgress)

                Text("Downloading — \(Int(model.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else if model.isDownloaded {
            if isActive {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Use This Model") {
                    coordinator.selectModel(model.id)
                }
                .buttonStyle(.bordered)
            }
        } else {
            Button("Download") {
                coordinator.selectModel(model.id)
                if !modelManager.startDownload(model.id) {
                    modelManager.refreshModels()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func compactModelRow(model: ModelManager.Model) -> some View {
        let isActive = coordinator.selectedModelId == model.id
        return card(
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.callout.weight(.medium))
                    Text("\(model.description) · \(model.sizeHint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                modelAction(model: model, isActive: isActive)
                    .frame(minWidth: 110, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        )
    }

    private func isBuiltIn(modelId: String) -> Bool {
        AppMode.modelDefinition(for: modelId)?.isBuiltIn ?? false
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.bottom, 14)

            Text("You're all set")
                .font(.system(size: 30, weight: .bold))

            HStack(spacing: 8) {
                Text("Press")
                    .foregroundStyle(.secondary)

                hotkeyKeycaps

                Text("and start talking.")
                    .foregroundStyle(.secondary)
            }
            .font(.title3)
            .padding(.top, 10)

            tryItField
                .padding(.top, 28)

            Text("Change the hotkey, language, or model anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

            Spacer()
        }
    }

    private var hotkeyKeycaps: some View {
        HStack(spacing: 4) {
            ForEach(Array(hotkeyKeycapLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.title3.weight(.medium))
                    .padding(.horizontal, label.count > 1 ? 10 : 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.quaternary)
                            .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
                    )
            }
        }
    }

    private var hotkeyKeycapLabels: [String] {
        HotkeyShortcut(
            keyCode: UInt32(max(0, hotkeyKeyCode)),
            modifiers: UInt32(max(0, hotkeyModifiers))
        ).keycapLabels
    }

    private var tryItField: some View {
        VStack(spacing: 6) {
            TextEditor(text: $tryItText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: 440)
                .frame(height: 76)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quinary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if tryItText.isEmpty {
                        Text(tryItPlaceholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var tryItPlaceholder: String {
        if isClipboardOutputMode {
            return "Try it: click here, press the hotkey and speak — then paste with ⌘V."
        }
        return "Try it: click here, press the hotkey, and say hello…"
    }

    private var isClipboardOutputMode: Bool {
        TypedSettings[.outputMode] == TypingService.OutputMode.clipboard.rawValue
    }

    // MARK: - Shared helpers

    private var popularLanguages: [(name: String, code: String)] {
        LanguageModelCatalog.popularLanguages()
    }

    private var allLanguages: [(name: String, code: String)] {
        LanguageModelCatalog.allLanguages()
    }

    private var selectedLanguageName: String {
        let code = coordinator.onboardingSelectedLanguage
        if code == "auto" { return "auto-detect" }
        return Constants.sortedLanguages.first { $0.code == code }?.name ?? code
    }
}

#Preview {
    OnboardingView(coordinator: OnboardingCoordinator(), onComplete: {}, onAppearAction: {})
}
