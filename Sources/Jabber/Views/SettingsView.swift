import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("outputMode") private var outputMode = "paste"
    @AppStorage("hotkeyDisplay") private var hotkeyDisplay = "⌥ Space"
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
        .frame(width: 450, height: 400)
        .onAppear {
            modelManager.refreshModels()
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { }
        } message: { message in
            Text(message)
        }
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
                    Text(hotkeyDisplay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text("Hotkey customization will be available in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkey")
            }

            Section {
                Picker("Language", selection: $selectedLanguage) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    ForEach(Constants.sortedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Text("Select a specific language or use auto-detect to identify it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Transcription Language")
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
                            guard selectedModel != model.id else { return }
                            selectedModel = model.id
                            NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
                        },
                        onDownload: {
                            Task {
                                do {
                                    try await modelManager.downloadModel(model.id)
                                } catch {
                                    errorMessage = "Failed to download \(model.name): \(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        },
                        onDelete: {
                            do {
                                try modelManager.deleteModel(model.id)
                            } catch {
                                errorMessage = "Failed to delete \(model.name): \(error.localizedDescription)"
                                showError = true
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
                    .frame(height: 120)
                    .font(.body.monospaced())

                Text("Add names, technical terms, or jargon to improve recognition. One per line or comma-separated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Custom Vocabulary")
            }
        }
        .formStyle(.grouped)
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

            if model.isDownloading {
                ProgressView(value: model.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 80)

                Text("\(Int(model.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 35, alignment: .trailing)
            } else if model.isDownloaded {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Button("Select") {
                        onSelect()
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete model")
            } else {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.bordered)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded {
                onSelect()
            }
        }
    }
}

#Preview {
    SettingsView()
}
