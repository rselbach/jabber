import SwiftUI

/// Transcript post-processing configuration.
struct PostProcessingPage: View {
    @AppStorage(AppSettingKey.postProcessingEnabled) private var postProcessingEnabled = false
    @AppStorage(AppSettingKey.postProcessingProviderKind) private var postProcessingProviderKindRaw = PostProcessingProviderKind.defaultValue.rawValue
    @AppStorage(AppSettingKey.openRouterModel) private var openRouterModel = OpenRouterModelCatalog.defaultModelId
    @AppStorage(AppSettingKey.openCodeZenModel) private var openCodeZenModel = OpenCodeZenModelCatalog.defaultModelId
    @State private var appleIntelligenceStatus = AppleIntelligenceStatus.current()

    var body: some View {
        Form {
            Section {
                Toggle("Post-process transcripts", isOn: $postProcessingEnabled)

                if postProcessingEnabled {
                    Picker("Post-processing provider", selection: $postProcessingProviderKindRaw) {
                        ForEach(PostProcessingProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind.rawValue)
                        }
                    }

                    switch selectedPostProcessingProviderKind {
                    case .appleIntelligence:
                        appleIntelligenceStatusRow

                        Text("Uses the on-device Apple Intelligence model to clean up the final transcript — fixing punctuation, removing filler words and self-corrections — before typing it. Falls back to the raw transcript if unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .openRouter:
                        CloudProviderAPIKeyField(provider: .openRouter)
                            .id(PostProcessingProviderKind.openRouter)

                        Picker("Model", selection: $openRouterModel) {
                            ForEach(OpenRouterModelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }

                        Text("Cloud post-processing sends your transcript to OpenRouter and the selected model provider for processing. The API key is stored in your macOS Keychain, not in preferences. Falls back to the raw transcript if the request fails.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .openCodeZen:
                        CloudProviderAPIKeyField(provider: .openCodeZen)
                            .id(PostProcessingProviderKind.openCodeZen)

                        Picker("Model", selection: $openCodeZenModel) {
                            ForEach(OpenCodeZenModelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }

                        Text("Cloud post-processing sends your transcript to OpenCode Zen and the selected model provider for processing. Jabber offers stable paid models only; Zen's temporary free models are excluded because submitted data may be used for model improvement. The API key is stored in your macOS Keychain. Falls back to the raw transcript if the request fails.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PostProcessingTestRow(
                        isProviderUnavailable: selectedPostProcessingProviderKind == .appleIntelligence
                            && !appleIntelligenceStatus.isAvailable
                    )
                    // A result belongs to one provider and model; start over on a change.
                    .id(testConfiguration)
                }
            } header: {
                Text("Post-Processing")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appleIntelligenceStatus = AppleIntelligenceStatus.current()
        }
        // Picks up Apple Intelligence being turned on in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appleIntelligenceStatus = AppleIntelligenceStatus.current()
        }
    }

    private var appleIntelligenceStatusRow: some View {
        HStack {
            Label {
                Text(appleIntelligenceStatus.message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: appleIntelligenceStatus.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appleIntelligenceStatus.isAvailable ? .green : .orange)
            }

            Spacer()

            if appleIntelligenceStatus.canFixInSettings {
                Button("Open Settings") {
                    AppleIntelligenceStatus.openSettings()
                }
            }
        }
    }

    private var selectedPostProcessingProviderKind: PostProcessingProviderKind {
        PostProcessingProviderKind(rawValue: postProcessingProviderKindRaw) ?? .defaultValue
    }

    private var testConfiguration: String {
        switch selectedPostProcessingProviderKind {
        case .appleIntelligence:
            return PostProcessingProviderKind.appleIntelligence.rawValue
        case .openRouter:
            return "\(PostProcessingProviderKind.openRouter.rawValue)/\(openRouterModel)"
        case .openCodeZen:
            return "\(PostProcessingProviderKind.openCodeZen.rawValue)/\(openCodeZenModel)"
        }
    }
}

/// Runs sample text through the selected provider with the saved settings,
/// the same way a dictation would, and shows the cleaned-up result.
private struct PostProcessingTestRow: View {
    let isProviderUnavailable: Bool

    static let sampleText = "um so tell troy and abed that the study group meets at three no wait four in the library thanks"

    @State private var result: String?
    @State private var isRunning = false
    @State private var testTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            HStack {
                Button("Test with Sample Text") {
                    runTest()
                }
                .disabled(isRunning || isProviderUnavailable)

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let result {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Said: \(Self.sampleText)")
                        .foregroundStyle(.secondary)
                    Text("Result: \(result.isEmpty ? "(nothing — the model removed it all)" : result)")
                }
                .font(.caption)
                .textSelection(.enabled)
            }
        }
        .alert(
            "Test Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    private func runTest() {
        // End editing first so a typed but unsaved API key is saved before
        // the provider reads it from the Keychain.
        NSApp.keyWindow?.makeFirstResponder(nil)
        result = nil
        isRunning = true
        testTask = Task {
            defer { isRunning = false }
            do {
                let output = try await RoutedPostProcessor().process(Self.sampleText)
                guard !Task.isCancelled else { return }
                result = output.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                // Leaving the page cancels the test; that is not a failure.
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Reusable Keychain-backed API key field for cloud post-processing providers.
/// Each instance loads and saves one provider's isolated credential.
private struct CloudProviderAPIKeyField: View {
    let provider: CloudPostProcessingProvider

    @State private var apiKey: String = ""
    @State private var keychainError: String?
    /// True only when the Keychain read succeeded. A failed read must not turn
    /// the field's initial empty value into an accidental credential deletion.
    @State private var didLoadKeySuccessfully = false
    /// Last successfully loaded/saved value, used to skip gratuitous writes.
    @State private var loadedApiKey: String = ""
    @State private var isLoadingAPIKey = false
    @State private var loadAPIKeyTask: Task<Void, Never>?

    var body: some View {
        Group {
            SecureField("\(provider.displayName) API key", text: $apiKey)
                .textContentType(.password)
                .onChange(of: apiKey) { _, _ in
                    cancelAPIKeyLoadAfterUserEdit()
                }
                .onSubmit {
                    saveAPIKey()
                }

            if let keychainError {
                Text(keychainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            loadAPIKey()
        }
        // Saves when editing ends, such as when Test is clicked, without
        // waiting for Return. Unchanged values are skipped.
        .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidEndEditingNotification)) { _ in
            saveAPIKey()
        }
        // The main window is retained when closed, so onDisappear is not
        // guaranteed to fire. Ignore close notifications from other windows.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == NSUserInterfaceItemIdentifier("com.rselbach.jabber.main") else { return }
            saveAPIKey()
        }
        // Cmd-Q bypasses both onDisappear and window-close notifications for
        // still-open windows.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveAPIKey()
        }
        .onDisappear {
            saveAPIKey()
        }
    }

    /// Loads this provider's API key from the Keychain into the SecureField.
    /// Keychain errors are surfaced as inline red text, not a modal alert.
    private func loadAPIKey() {
        loadAPIKeyTask?.cancel()
        isLoadingAPIKey = true

        loadAPIKeyTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    return try APIKeyLoadResult.success(provider.readKey() ?? "")
                } catch {
                    return APIKeyLoadResult.failure(error.localizedDescription)
                }
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                loadAPIKeyTask = nil
                isLoadingAPIKey = false

                switch result {
                case let .success(key):
                    apiKey = key
                    loadedApiKey = key
                    didLoadKeySuccessfully = true
                    keychainError = nil
                case let .failure(message):
                    // Don't treat the empty field as a deletion: a transient
                    // read failure (e.g. user cancelled the auth prompt) must
                    // not wipe the real stored key on the next save.
                    apiKey = ""
                    loadedApiKey = ""
                    didLoadKeySuccessfully = false
                    keychainError = message
                }

                // Reading the keychain can surface an auth prompt that
                // deactivates Jabber; bring it back to the front once the
                // prompt resolves so the main window doesn't end up stranded
                // behind other apps.
                NSApp.activate(ignoringOtherApps: false)
            }
        }
    }

    private func cancelAPIKeyLoadAfterUserEdit() {
        guard isLoadingAPIKey else { return }
        loadAPIKeyTask?.cancel()
        loadAPIKeyTask = nil
        isLoadingAPIKey = false
        didLoadKeySuccessfully = false
        loadedApiKey = ""
    }

    /// Persists the SecureField's API key to the Keychain. An empty/whitespace
    /// value deletes the stored key. Errors are surfaced as inline red text.
    private func saveAPIKey() {
        guard APIKeyPersistenceDecision.shouldPersist(
            didLoadSuccessfully: didLoadKeySuccessfully,
            isLoadInProgress: isLoadingAPIKey,
            loadedValue: loadedApiKey,
            currentValue: apiKey
        ) else { return }

        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try provider.deleteKey()
            } else {
                try provider.saveKey(trimmed)
            }
            apiKey = trimmed
            loadedApiKey = trimmed
            didLoadKeySuccessfully = true
            keychainError = nil
        } catch {
            keychainError = error.localizedDescription
        }
    }
}

private enum CloudPostProcessingProvider: Sendable {
    case openRouter
    case openCodeZen

    var displayName: String {
        switch self {
        case .openRouter:
            "OpenRouter"
        case .openCodeZen:
            "OpenCode Zen"
        }
    }

    func readKey() throws -> String? {
        switch self {
        case .openRouter:
            try OpenRouterKeychain.readKey()
        case .openCodeZen:
            try OpenCodeZenKeychain.readKey()
        }
    }

    func saveKey(_ key: String) throws {
        switch self {
        case .openRouter:
            try OpenRouterKeychain.saveKey(key)
        case .openCodeZen:
            try OpenCodeZenKeychain.saveKey(key)
        }
    }

    func deleteKey() throws {
        switch self {
        case .openRouter:
            try OpenRouterKeychain.deleteKey()
        case .openCodeZen:
            try OpenCodeZenKeychain.deleteKey()
        }
    }
}

/// Decides whether a cloud API key field should write to the Keychain. Guards
/// against failure modes that could otherwise clobber
/// the user's real stored key:
///
/// - A transient keychain read failure (e.g. user cancelled the auth prompt)
///   blanks the SecureField. Without the failed-load empty-value guard, the
///   next `onDisappear` (every sidebar switch) would treat that blank as
///   "delete stored key" and wipe it. Non-empty values are still safe to save.
/// - The field is unchanged since the last successful load. Skipping the
///   write avoids a gratuitous `SecItemUpdate` on every sidebar switch.
/// - The async keychain load is still in flight. Close/terminate notifications
///   can arrive before the read completes, and saving the initial empty field
///   would clobber a real stored key.
enum APIKeyPersistenceDecision {
    static func shouldPersist(
        didLoadSuccessfully: Bool,
        isLoadInProgress: Bool,
        loadedValue: String,
        currentValue: String
    ) -> Bool {
        guard !isLoadInProgress else { return false }
        let normalizedCurrentValue = normalized(currentValue)
        guard didLoadSuccessfully else { return !normalizedCurrentValue.isEmpty }
        return normalizedCurrentValue != normalized(loadedValue)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum APIKeyLoadResult: Sendable {
    case success(String)
    case failure(String)
}
