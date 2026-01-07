import SwiftUI

struct MenuBarView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @AppStorage("selectedLanguage") private var selectedLanguage = Constants.defaultLanguage
    @State private var modelManager = ModelManager.shared
    @ObservedObject var updaterController: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Press ⌥ Space to dictate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if modelManager.downloadedModels.isEmpty {
                    Text("No models downloaded")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Model:")
                        Picker("", selection: $selectedModel) {
                            ForEach(modelManager.downloadedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Language:")
                        Picker("", selection: $selectedLanguage) {
                            Text("Auto-detect").tag("auto")
                            Divider()
                            ForEach(Constants.sortedLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            Divider()

            Button("Check for Updates...") {
                updaterController.checkForUpdates()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(!updaterController.canCheckForUpdates)

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            modelManager.refreshModels()
        }
    }
}

#Preview {
    MenuBarView(updaterController: UpdaterController())
}
