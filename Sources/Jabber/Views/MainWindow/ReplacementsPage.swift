import os
import SwiftUI

/// Instant Replacement rules: phrases Jabber swaps for literal text as the
/// final pass before typing.
struct ReplacementsPage: View {
    private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "ReplacementsPage")

    @State private var entries: [ReplacementEntry] = []
    /// The stored form of the rules as last loaded or written. Flushes compare
    /// against it, so just visiting the page never rewrites the preference
    /// (not even one the codec failed to decode).
    @State private var savedEntries: [ReplacementEntry] = []
    @State private var persistDebounceTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                if entries.isEmpty {
                    Text("No rules yet. Add a phrase Jabber keeps getting wrong and what it should type instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach($entries) { $entry in
                    ReplacementEntryRow(entry: $entry) { [id = entry.id] in
                        entries.removeAll { $0.id == id }
                    }
                }
                Button {
                    entries.append(ReplacementEntry(triggers: [], replacement: ""))
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Instant Replacement")
            } footer: {
                Text("Runs after transcription and post-processing, right before Jabber types. Matching ignores case and only hits whole words. Separate several phrases with commas. A rule does nothing until both fields are filled in.")
            }
        }
        .formStyle(.grouped)
        // Flush before loading so a reload can never clobber edits still
        // waiting on the debounce.
        .onAppear {
            flushPersist()
            loadEntries()
        }
        .onChange(of: entries) { _, _ in
            schedulePersist()
        }
        // The main window is retained when closed, so onDisappear is not
        // guaranteed to fire. Ignore close notifications from other windows.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == NSUserInterfaceItemIdentifier("com.rselbach.jabber.main") else { return }
            flushPersist()
        }
        // Cmd-Q inside the debounce window kills the pending write and skips
        // both onDisappear and window-close notifications for open windows.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushPersist()
        }
        // Sidebar switches remove this view; flush so navigating away during
        // the debounce window keeps the last edit.
        .onDisappear {
            flushPersist()
        }
    }

    private func loadEntries() {
        let stored = TypedSettings.replacementEntries
        entries = stored
        savedEntries = ReplacementEntryEditing.entriesToPersist(stored)
    }

    private func schedulePersist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Replacement rules debounce failed: \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }
            flushPersist()
        }
    }

    /// Cancels any pending debounced write and stores the rules now if they
    /// changed since the last load or write.
    private func flushPersist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
        let toPersist = ReplacementEntryEditing.entriesToPersist(entries)
        guard toPersist != savedEntries else { return }
        TypedSettings.replacementEntries = toPersist
        savedEntries = toPersist
    }
}

/// Editor for a single replacement rule: comma-separated triggers above, the
/// literal replacement below, with a delete control.
private struct ReplacementEntryRow: View {
    @Binding var entry: ReplacementEntry
    let onDelete: () -> Void

    /// Raw comma-separated trigger text, held apart from `entry.triggers` so
    /// typing "troy, " isn't normalized back to "troy" under the cursor.
    /// Seeded once from the stored triggers; only user edits write back.
    @State private var triggerText: String

    init(entry: Binding<ReplacementEntry>, onDelete: @escaping () -> Void) {
        _entry = entry
        self.onDelete = onDelete
        _triggerText = State(initialValue: ReplacementEntryEditing.triggerText(from: entry.wrappedValue.triggers))
    }

    var body: some View {
        // The grouped Form promotes a TextField's title to a leading label
        // column and right-aligns the text. Render captions explicitly and
        // hide the field labels so the fields span the row; the hidden titles
        // remain the fields' accessibility labels.
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Replace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Replace", text: $triggerText, prompt: Text("greendale, greendale cc"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .onChange(of: triggerText) { _, newValue in
                        entry.triggers = ReplacementEntryEditing.triggers(from: newValue)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("With")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                HStack {
                    TextField("With", text: $entry.replacement, prompt: Text("Greendale Community College"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                    Button {
                        onDelete()
                    } label: {
                        Label("Delete Rule", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Delete rule")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pure helpers behind the replacement rule editor: parsing the trigger field
/// and choosing which rows get stored.
enum ReplacementEntryEditing {
    /// Splits the comma-separated trigger field into trimmed, non-empty
    /// triggers, so a half-typed "troy, " never stores an empty trigger.
    static func triggers(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Formats stored triggers for the trigger field.
    static func triggerText(from triggers: [String]) -> String {
        triggers.joined(separator: ", ")
    }

    /// The rows worth storing, in order and unmodified. Blank rows (an
    /// abandoned Add Rule) are dropped. Partial rows are kept so a half-written
    /// rule survives closing the window; `ReplacementWordsResolver` ignores a
    /// rule until it has both a trigger and a replacement.
    static func entriesToPersist(_ entries: [ReplacementEntry]) -> [ReplacementEntry] {
        entries.filter { entry in
            !isBlank(entry.replacement) || entry.triggers.contains { !isBlank($0) }
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
