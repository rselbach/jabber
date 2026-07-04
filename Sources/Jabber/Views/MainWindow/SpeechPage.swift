import SwiftUI

/// Transcription language and speech model management.
struct SpeechPage: View {
    @AppStorage(AppSettingKey.selectedModel) private var selectedModel = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
    @AppStorage(AppSettingKey.selectedLanguage) private var selectedLanguage = Constants.defaultLanguage

    @State private var modelManager = ModelManager.shared
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pendingDeleteModelId: String?
    @State private var pendingDeleteModelName: String?

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
                            pendingDeleteModelId = model.id
                            pendingDeleteModelName = model.name
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
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.modelDownloadStateDidChange)) { notification in
            guard let state = notification.object as? ModelDownloadState else { return }
            guard state.phase == .failed, !state.isCancelled else { return }

            let modelName = modelManager.models.first { $0.id == state.modelId }?.name ?? state.modelId
            let details = state.errorDescription ?? state.status
            presentError("Failed to download \(modelName): \(details)")
        }
        .alert("Delete model", isPresented: Binding(
            get: { pendingDeleteModelId != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteModelId = nil
                    pendingDeleteModelName = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let modelId = pendingDeleteModelId,
                      let modelName = pendingDeleteModelName else {
                    pendingDeleteModelId = nil
                    return
                }
                do {
                    try modelManager.deleteModel(modelId)
                } catch {
                    presentError("Failed to delete \(modelName): \(error.localizedDescription)")
                }
                pendingDeleteModelId = nil
                pendingDeleteModelName = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModelId = nil
                pendingDeleteModelName = nil
            }
        } message: {
            Text("Delete \(pendingDeleteModelName ?? "")? This action removes local model files and cannot be undone.")
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
