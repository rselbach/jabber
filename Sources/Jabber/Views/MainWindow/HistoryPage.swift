import AppKit
import SwiftUI

/// Local dictation history: retention toggle and recent sessions.
struct HistoryPage: View {
    @AppStorage(AppSettingKey.historyEnabled) private var historyEnabled = true

    @State private var historyEntries: [DictationHistoryEntry] = []
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Form {
            Section {
                Toggle("Save dictation history", isOn: $historyEnabled)

                Text("Jabber keeps your transcripts on this Mac for a month.")
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
                    Text(historyEnabled ? "No saved dictations yet." : "History is disabled.")
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
            guard let audioURL = DictationHistoryStore.shared.audioURL(for: entry),
                  FileManager.default.fileExists(atPath: audioURL.path) else {
                errorMessage = "Audio file for this session is missing. It may have been removed by retention cleanup."
                showError = true
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([audioURL])
        }
    }
}
