import SwiftUI

struct SettingsView: View {
    @ObservedObject var updaterController: UpdaterController

    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("outputMode") private var outputMode = "paste"
    @AppStorage("vocabularyPrompt") private var vocabularyPrompt = ""
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage

    @State private var modelManager = ModelManager.shared
    @State private var errorMessage: String?
    @State private var showError = false

    @State private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tag("general")
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            modelsTab
                .tag("models")
                .tabItem {
                    Label("Models", systemImage: "cube.box")
                }

            vocabularyTab
                .tag("vocabulary")
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }
        }
        .frame(width: 520, height: 560)
        .onAppear {
            modelManager.refreshModels()
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { }
        } message: { message in
            Text(message)
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("After transcription", selection: $outputMode) {
                    Text("Copy to clipboard").tag("clipboard")
                    Text("Paste into active app").tag("paste")
                }
                .pickerStyle(.radioGroup)

                if outputMode == "paste" {
                    Text("Requires Accessibility permission in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Output")
            }

            Section {
                HStack {
                    Text("Press to talk:")
                    Spacer()
                    HotkeyRecorderView()
                }

                Text("Click to record a new shortcut. Click again to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkey")
            }

            Section {
                LanguagePicker(selectedLanguage: $selectedLanguage)

                Text("Select a specific language or use auto-detect to identify it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Language")
            }

            Section {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { updaterController.automaticallyChecksForUpdates },
                        set: { enabled in
                            updaterController.setAutomaticallyChecksForUpdates(enabled)
                        }
                    )
                )
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    private var modelsTab: some View {
        Form {
            Section {
                ForEach(modelManager.models) { model in
                    ModelRow(
                        model: model,
                        isSelected: selectedModel == model.id,
                        onSelect: {
                            guard model.isDownloaded else { return }
                            let previousModelId = selectedModel
                            guard modelManager.selectModel(model.id, previousModelId: previousModelId) else { return }
                            selectedModel = model.id
                        },
                        onDownload: {
                            Task {
                                do {
                                    try await modelManager.downloadModel(model.id)
                                } catch {
                                    presentError("Failed to download \(model.name): \(error.localizedDescription)")
                                }
                            }
                        },
                        onDelete: {
                            do {
                                try modelManager.deleteModel(model.id)
                            } catch {
                                presentError("Failed to delete \(model.name): \(error.localizedDescription)")
                            }
                        }
                    )
                }

                Text("Larger models are more accurate but slower and use more memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Models")
            }
        }
        .formStyle(.grouped)
    }

    private var vocabularyTab: some View {
        Form {
            Section {
                TextEditor(text: $vocabularyPrompt)
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .font(.body.monospaced())

                Text("Add names, technical terms, or jargon to improve recognition. One per line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Custom Vocabulary")
            }
        }
        .formStyle(.grouped)
    }
}

struct LanguagePicker: View {
    @Binding var selectedLanguage: String

    var body: some View {
        Picker("Language", selection: $selectedLanguage) {
            Text("Auto-detect").tag("auto")
            Divider()
            ForEach(Constants.sortedLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        }
    }
}

struct ModelRow: View {
    let model: ModelManager.Model
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(model.sizeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingContent
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded {
                onSelect()
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if model.isDownloading {
            downloadingContent
        } else if model.isDownloaded {
            downloadedContent
        } else {
            downloadButton
        }
    }

    @ViewBuilder
    private var downloadingContent: some View {
        ProgressView(value: model.downloadProgress)
            .progressViewStyle(.linear)
            .frame(width: 80)

        Text("\(Int(model.downloadProgress * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 35, alignment: .trailing)
    }

    @ViewBuilder
    private var downloadedContent: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } else {
            selectButton
        }

        deleteButton
    }

    private var selectButton: some View {
        Button("Select") {
            onSelect()
        }
        .buttonStyle(.borderless)
    }

    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Delete model")
    }

    private var downloadButton: some View {
        Button("Download") {
            onDownload()
        }
        .buttonStyle(.bordered)
    }
}
