import SwiftUI

/// Custom vocabulary and instant-replacement configuration.
struct VocabularyPage: View {
    @AppStorage(AppSettingKey.vocabularyPrompt) private var vocabularyPrompt = ""
    @AppStorage(AppSettingKey.replacementEntries) private var replacementEntriesRaw = ""

    @State private var wordRows: [VocabularyWordRow] = []
    @State private var entries: [ReplacementEntry] = []
    @State private var persistDebounceTask: Task<Void, Never>?

    var body: some View {
        Form {
            instantReplacementSection
            customWordsSection
        }
        .formStyle(.grouped)
        .onAppear { loadState() }
        // The main window is retained when closed, so onDisappear is not
        // guaranteed to fire on window close; persist on window close as well.
        // Filter to the main window only — willCloseNotification fires for every
        // window.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == NSUserInterfaceItemIdentifier("com.rselbach.jabber.main") else { return }
            persistAll()
        }
        // Quitting (Cmd-Q) within the 500ms debounce window bypasses both the
        // debounce task (it dies with the process) and willCloseNotification
        // (applicationWillTerminate doesn't guarantee it for still-open
        // windows). Flush on app termination so a last keystroke isn't lost.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persistAll()
        }
        // Sidebar switches remove this view from the hierarchy; flush there too
        // so navigating away during the debounce window isn't lost.
        .onDisappear {
            persistAll()
        }
    }

    // MARK: - Instant Replacement

    private var instantReplacementSection: some View {
        Section {
            if entries.isEmpty {
                Text("No replacement rules yet. Add a phrase to replace and what Jabber should type instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($entries) { $entry in
                ReplacementEntryRow(entry: $entry) {
                    deleteEntry(entry)
                }
                .onChange(of: entry) { _, _ in
                    schedulePersist()
                }
            }
            Button {
                addEntry()
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Instant Replacement")
        } footer: {
            Text("Replaces trigger phrases with your text as a final pass after transcription and post-processing. Matching is case-insensitive and respects word boundaries. Separate multiple triggers with commas.")
        }
    }

    // MARK: - Custom Words

    private var customWordsSection: some View {
        Section {
            if wordRows.isEmpty {
                Text("No custom words yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($wordRows) { $row in
                HStack {
                    TextField("Word or phrase", text: $row.text)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: row.text) { _, _ in
                            schedulePersist()
                        }
                    Button {
                        deleteWordRow(row)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete word")
                }
            }
            Button {
                addWordRow()
            } label: {
                Label("Add Word", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Custom Words")
        } footer: {
            Text("Words and phrases that bias Qwen3 recognition. Ignored by Nemotron and Apple Speech.")
        }
    }

    // MARK: - State sync

    private func loadState() {
        entries = ReplacementEntriesCodec.decode(replacementEntriesRaw)
        wordRows = vocabularyPrompt
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { VocabularyWordRow(text: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
    }

    private func persistAll() {
        flushPersist()
    }

    private func schedulePersist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            persistEntries()
            persistWords()
        }
    }

    private func flushPersist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
        persistEntries()
        persistWords()
    }

    private func persistEntries() {
        replacementEntriesRaw = ReplacementEntriesCodec.encode(entries)
    }

    private func persistWords() {
        vocabularyPrompt = wordRows
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func addEntry() {
        entries.append(ReplacementEntry(triggers: [], replacement: ""))
        persistEntries()
    }

    private func deleteEntry(_ entry: ReplacementEntry) {
        entries.removeAll { $0.id == entry.id }
        persistEntries()
    }

    private func addWordRow() {
        wordRows.append(VocabularyWordRow(text: ""))
    }

    private func deleteWordRow(_ row: VocabularyWordRow) {
        wordRows.removeAll { $0.id == row.id }
        persistWords()
    }
}

/// A single editable custom-word row. Identified by a stable UUID so SwiftUI
/// preserves TextField focus across add/delete operations on the list.
private struct VocabularyWordRow: Identifiable {
    let id = UUID()
    var text: String
}

/// Editor for a single replacement rule: comma-separated triggers above, the
/// literal replacement below, with a delete control.
private struct ReplacementEntryRow: View {
    @Binding var entry: ReplacementEntry
    let onDelete: () -> Void

    /// Raw comma-separated trigger text. Held separately from `entry.triggers`
    /// so the user can type "troy, " without the parser immediately stripping
    /// the trailing comma+space and fighting the cursor.
    @State private var triggerText: String = ""

    var body: some View {
        // The grouped Form promotes a `TextField("Label", text:)` to a labeled
        // form control: "Label" -> leading column, field -> trailing slot with
        // trailing-aligned text. So we render explicit `Text` labels and mark
        // the fields `.labelsHidden()` so Form has no title to promote. This is
        // what makes the fields span the row and read from the leading edge.
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trigger(s) — separate with commas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("cloud-idp, cloudidp", text: $triggerText)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .onChange(of: triggerText) { _, newValue in
                        entry.triggers = parseTriggers(newValue)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Replace with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("CloudIDP", text: $entry.replacement)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete rule")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { triggerText = entry.triggers.joined(separator: ", ") }
    }

    private func parseTriggers(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
