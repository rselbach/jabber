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

                Text("Select a specific language or use auto-detect to identify it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Language")
            }

            Section {
                ForEach(modelManager.models) { model in
                    ModelRow(
                        model: model,
                        isSelected: selectedModel == model.id,
                        onSelect: {
                            guard model.isDownloaded else { return }
                            if modelManager.selectModel(model.id) {
                                selectedModel = model.id
                            }
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

                Text("Larger models are more accurate but slower and use more memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
