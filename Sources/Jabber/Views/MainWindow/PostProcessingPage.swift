import SwiftUI

/// Transcript post-processing configuration.
struct PostProcessingPage: View {
    @AppStorage(AppSettingKey.postProcessingEnabled) private var postProcessingEnabled = false
    @AppStorage(AppSettingKey.postProcessingProviderKind) private var postProcessingProviderKindRaw = PostProcessingProviderKind.defaultValue.rawValue
    @AppStorage(AppSettingKey.openRouterModel) private var openRouterModel = OpenRouterModelCatalog.defaultModelId

    @State private var openRouterApiKey: String = ""
    @State private var keychainError: String?
    /// True only when `loadOpenRouterAPIKey` read the keychain successfully.
    /// When false (read failed, e.g. user cancelled the auth prompt), the
    /// empty field must not be persisted back as a deletion on the next
    /// `onDisappear` — that would clobber the real stored key.
    @State private var didLoadKeySuccessfully = false
    /// Last value successfully loaded from the keychain. Used to skip
    /// gratuitous `SecItemUpdate` calls when the field is unchanged.
    @State private var loadedApiKey: String = ""
    @State private var isLoadingOpenRouterAPIKey = false
    @State private var loadOpenRouterAPIKeyTask: Task<Void, Never>?

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
                        Text("Uses the on-device Apple Intelligence model to clean up the final transcript — fixing punctuation, removing filler words and self-corrections — before typing it. Requires an Apple Intelligence-capable Mac with Apple Intelligence turned on. Falls back to the raw transcript if unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .openRouter:
                        SecureField("OpenRouter API key", text: $openRouterApiKey)
                            .textContentType(.password)
                            .onChange(of: openRouterApiKey) { _, _ in
                                cancelOpenRouterAPIKeyLoadAfterUserEdit()
                            }
                            .onSubmit {
                                saveOpenRouterAPIKey()
                            }

                        Picker("Model", selection: $openRouterModel) {
                            ForEach(OpenRouterModelCatalog.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }

                        if let keychainError {
                            Text(keychainError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Text("Cloud post-processing sends your transcript to OpenRouter and the selected model provider for processing. The API key is stored in your macOS Keychain, not in preferences. Falls back to the raw transcript if the request fails.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Post-Processing")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadOpenRouterAPIKey()
        }
        // The main window is retained when closed, so onDisappear is not
        // guaranteed to fire; persist the key on window close as well.
        // Filter to the main window only — willCloseNotification fires for
        // every window (onboarding, migration notice, etc.) and acting on
        // those would clobber the SecureField mid-typing and could silently
        // delete a saved key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == NSUserInterfaceItemIdentifier("com.rselbach.jabber.main") else { return }
            saveOpenRouterAPIKey()
        }
        // Quitting (Cmd-Q) bypasses both onDisappear and
        // willCloseNotification for still-open windows. Flush on app
        // termination so a pasted key isn't lost.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveOpenRouterAPIKey()
        }
        .onDisappear {
            saveOpenRouterAPIKey()
        }
    }

    private var selectedPostProcessingProviderKind: PostProcessingProviderKind {
        PostProcessingProviderKind(rawValue: postProcessingProviderKindRaw) ?? .defaultValue
    }

    /// Loads the OpenRouter API key from the Keychain into the SecureField.
    /// Keychain errors are surfaced as inline red text, not a modal alert.
    private func loadOpenRouterAPIKey() {
        loadOpenRouterAPIKeyTask?.cancel()
        isLoadingOpenRouterAPIKey = true

        loadOpenRouterAPIKeyTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    return try APIKeyLoadResult.success(OpenRouterKeychain.readKey() ?? "")
                } catch {
                    return APIKeyLoadResult.failure(error.localizedDescription)
                }
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                loadOpenRouterAPIKeyTask = nil
                isLoadingOpenRouterAPIKey = false

                switch result {
                case let .success(key):
                    openRouterApiKey = key
                    loadedApiKey = key
                    didLoadKeySuccessfully = true
                    keychainError = nil
                case let .failure(message):
                    // Don't treat the empty field as a deletion: a transient
                    // read failure (e.g. user cancelled the auth prompt) must
                    // not wipe the real stored key on the next save.
                    openRouterApiKey = ""
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

    private func cancelOpenRouterAPIKeyLoadAfterUserEdit() {
        guard isLoadingOpenRouterAPIKey else { return }
        loadOpenRouterAPIKeyTask?.cancel()
        loadOpenRouterAPIKeyTask = nil
        isLoadingOpenRouterAPIKey = false
        didLoadKeySuccessfully = false
        loadedApiKey = ""
    }

    /// Persists the SecureField's API key to the Keychain. An empty/whitespace
    /// value deletes the stored key. Errors are surfaced as inline red text.
    private func saveOpenRouterAPIKey() {
        guard APIKeyPersistenceDecision.shouldPersist(
            didLoadSuccessfully: didLoadKeySuccessfully,
            isLoadInProgress: isLoadingOpenRouterAPIKey,
            loadedValue: loadedApiKey,
            currentValue: openRouterApiKey
        ) else { return }

        let trimmed = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try OpenRouterKeychain.deleteKey()
            } else {
                try OpenRouterKeychain.saveKey(trimmed)
            }
            openRouterApiKey = trimmed
            loadedApiKey = trimmed
            didLoadKeySuccessfully = true
            keychainError = nil
        } catch {
            keychainError = error.localizedDescription
        }
    }
}

/// Decides whether `PostProcessingPage.saveOpenRouterAPIKey` should write to
/// the keychain. Guards against two failure modes that previously clobbered
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
