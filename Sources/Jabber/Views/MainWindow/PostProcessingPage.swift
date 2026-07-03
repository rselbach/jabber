import SwiftUI

/// Transcript post-processing configuration.
struct PostProcessingPage: View {
    @AppStorage(AppSettingKey.postProcessingEnabled) private var postProcessingEnabled = false
    @AppStorage(AppSettingKey.postProcessingProviderKind) private var postProcessingProviderKindRaw = PostProcessingProviderKind.defaultValue.rawValue
    @AppStorage(AppSettingKey.openRouterModel) private var openRouterModel = OpenRouterModelCatalog.defaultModelId

    @State private var openRouterApiKey: String = ""
    @State private var keychainError: String?

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
            // Reading the keychain can surface an auth prompt that deactivates
            // Jabber; bring it back to the front once the prompt resolves so
            // the main window doesn't end up stranded behind other apps.
            NSApp.activate()
        }
        .onDisappear {
            saveOpenRouterAPIKey()
        }
        // The main window is retained when closed, so onDisappear is not
        // guaranteed to fire; persist the key on window close as well.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            saveOpenRouterAPIKey()
        }
    }

    private var selectedPostProcessingProviderKind: PostProcessingProviderKind {
        PostProcessingProviderKind(rawValue: postProcessingProviderKindRaw) ?? .defaultValue
    }

    /// Loads the OpenRouter API key from the Keychain into the SecureField.
    /// Keychain errors are surfaced as inline red text, not a modal alert.
    private func loadOpenRouterAPIKey() {
        do {
            openRouterApiKey = try OpenRouterKeychain.readKey() ?? ""
            keychainError = nil
        } catch {
            openRouterApiKey = ""
            keychainError = error.localizedDescription
        }
    }

    /// Persists the SecureField's API key to the Keychain. An empty/whitespace
    /// value deletes the stored key. Errors are surfaced as inline red text.
    private func saveOpenRouterAPIKey() {
        let trimmed = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try OpenRouterKeychain.deleteKey()
            } else {
                try OpenRouterKeychain.saveKey(trimmed)
            }
            openRouterApiKey = trimmed
            keychainError = nil
        } catch {
            keychainError = error.localizedDescription
        }
    }
}
