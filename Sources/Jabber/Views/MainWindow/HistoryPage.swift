import AppKit
import SwiftUI

/// Local dictation history: retention toggle and recent sessions.
struct HistoryPage: View {
    @AppStorage(AppSettingKey.saveHistoryEnabled) private var saveHistoryEnabled = false

    @State private var historyEntries: [DictationHistoryEntry] = []
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Form {
            Section {
                Toggle("Save dictation history", isOn: $saveHistoryEnabled)

                Text("When enabled, Jabber saves recent audio and transcripts locally for debugging. Retention is capped at 50 sessions or 500MB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Refresh") {
                        refreshHistoryEntries()
                    }
                    .buttonStyle(.borderless)

                    Button("Reveal History Folder") {
                        revealHistoryFolder()
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Local Debug History")
            }

            Section {
                if historyEntries.isEmpty {
                    Text(saveHistoryEnabled ? "No saved dictations yet." : "History is disabled.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyEntries) { entry in
                        HistoryEntryRow(entry: entry) {
                            revealHistoryEntry(entry)
                        }
                    }
                }
            } header: {
                Text("Recent Sessions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshHistoryEntries()
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func refreshHistoryEntries() {
        Task { @MainActor in
            historyEntries = await DictationHistoryStore.shared.entries()
        }
    }

    private func revealHistoryFolder() {
        Task { @MainActor in
            let historyDirectoryURL = DictationHistoryStore.shared.historyDirectoryURL()
            do {
                try FileManager.default.createDirectory(at: historyDirectoryURL, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([historyDirectoryURL])
            } catch {
                errorMessage = "Failed to open history folder: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func revealHistoryEntry(_ entry: DictationHistoryEntry) {
        Task { @MainActor in
            let audioURL = DictationHistoryStore.shared.audioURL(for: entry)
            NSWorkspace.shared.activateFileViewerSelecting([audioURL])
        }
    }
}
