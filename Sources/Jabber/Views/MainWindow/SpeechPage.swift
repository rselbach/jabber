import SwiftUI

/// Transcription language and speech model management.
struct SpeechPage: View {
    @AppStorage(AppSettingKey.selectedModel) private var selectedModel = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
    @AppStorage(AppSettingKey.selectedLanguage) private var selectedLanguage = Constants.defaultLanguage

    @State private var modelManager = ModelManager.shared
    @State private var activeAlert: AlertState?
    @State private var isAlertPresented = false
    @State private var pendingAlerts: [AlertState] = []

    var body: some View {
        Form {
            Section {
                LanguagePicker(selectedLanguage: $selectedLanguage)

                languageCompatibilityNote
            } header: {
                Text("Transcription Language")
            }

            Section {
                ForEach(modelManager.models) { model in
                    ModelRow(
                        model: model,
                        isSelected: selectedModel == model.id,
                        unsupportedLanguageName: unsupportedLanguageName(for: model.id),
                        onSelect: {
                            select(model)
                        },
                        onDownload: {
                            _ = modelManager.startDownload(model.id)
                        },
                        onDelete: {
                            queueAlert(.deleteModel(id: model.id, name: model.name))
                        },
                        onCancelDownload: {
                            modelManager.cancelDownload(model.id)
                        }
                    )
                }
            } header: {
                Text("Speech Models")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            modelManager.refreshModels()
        }
        .alert(alertTitle, isPresented: $isAlertPresented, presenting: activeAlert) { state in
            switch state {
            case .error:
                Button("OK") {}
            case .deleteModel(let id, let name):
                Button("Delete", role: .destructive) {
                    do {
                        try modelManager.deleteModel(id)
                    } catch {
                        queueAlert(.error(message: "Failed to delete \(name): \(error.localizedDescription)"))
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: { state in
            switch state {
            case .error(let message):
                Text(message)
            case .deleteModel(_, let name):
                Text("Delete \(name)? This action removes local model files and cannot be undone.")
            }
        }
        .onChange(of: isAlertPresented) { _, isPresented in
            // When the current alert is dismissed, dequeue the next pending one
            // (if any). Mirrors the existing error-queue pattern, extended to
            // also serialize the delete confirmation so the two never race for
            // the single alert slot SwiftUI allows per view.
            guard !isPresented else { return }
            activeAlert = nil
            guard !pendingAlerts.isEmpty else { return }
            queueAlert(pendingAlerts.removeFirst())
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.modelDownloadStateDidChange)) { notification in
            guard let state = notification.object as? ModelDownloadState else { return }
            guard state.phase == .failed, !state.isCancelled else { return }

            let modelName = modelManager.models.first { $0.id == state.modelId }?.name ?? state.modelId
            let details = state.errorDescription ?? state.status
            queueAlert(.error(message: "Failed to download \(modelName): \(details)"))
        }
    }

    /// Says what the selected model will actually do with the selected
    /// language, and offers the fix when the pair cannot work.
    @ViewBuilder
    private var languageCompatibilityNote: some View {
        let modelName = AppMode.modelDefinition(for: selectedModel)?.name ?? selectedModel
        switch LanguageModelCatalog.compatibility(
            languageCode: selectedLanguage,
            modelId: selectedModel,
            systemLanguageCode: AppleSpeechProvider.locale(for: "auto").language.languageCode?.identifier
        ) {
        case .unsupported(let recommendedModelId):
            HStack {
                Label(
                    "\(modelName) can't transcribe \(languageName(for: selectedLanguage)), so dictation will come out garbled.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)

                Spacer()

                if let recommended = modelManager.models.first(where: { $0.id == recommendedModelId }) {
                    recommendedModelButton(recommended)
                }
            }
        case .supported:
            compatibilityCaption("\(modelName) supports \(languageName(for: selectedLanguage)).")
        case .detectsLanguage:
            compatibilityCaption("\(modelName) detects which of its supported languages you're speaking.")
        case .assumesLanguage(let code):
            compatibilityCaption("\(modelName) can't detect the language. It always transcribes \(languageName(for: code)).")
        case .usesSystemLanguage(let code?):
            compatibilityCaption("\(modelName) can't detect the language. It uses the system language, \(languageName(for: code)).")
        case .usesSystemLanguage(nil):
            compatibilityCaption("\(modelName) can't detect the language. It uses the system language.")
        case nil:
            EmptyView()
        }
    }

    private func compatibilityCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func recommendedModelButton(_ model: ModelManager.Model) -> some View {
        if model.isDownloading {
            Button("Downloading \(model.name)… \(Int(model.downloadProgress * 100))%") {}
                .disabled(true)
        } else if model.isDownloaded {
            Button("Use \(model.name)") {
                select(model)
            }
        } else {
            Button("Download \(model.name) (\(model.sizeHint))") {
                _ = modelManager.startDownload(model.id)
            }
        }
    }

    private func unsupportedLanguageName(for modelId: String) -> String? {
        guard !LanguageModelCatalog.supportsLanguage(selectedLanguage, modelId: modelId) else { return nil }
        return languageName(for: selectedLanguage)
    }

    private func languageName(for code: String) -> String {
        Constants.sortedLanguages.first { $0.code == code }?.name ?? code
    }

    private func select(_ model: ModelManager.Model) {
        guard model.isDownloaded else { return }
        if modelManager.selectModel(model.id) {
            selectedModel = model.id
        }
    }

    private var alertTitle: String {
        switch activeAlert {
        case .error: return "Error"
        case .deleteModel: return "Delete model"
        case .none: return ""
        }
    }

    private func queueAlert(_ state: AlertState) {
        guard !isAlertPresented else {
            pendingAlerts.append(state)
            return
        }
        activeAlert = state
        isAlertPresented = true
    }
}

private enum AlertState: Equatable {
    case error(message: String)
    case deleteModel(id: String, name: String)
}
