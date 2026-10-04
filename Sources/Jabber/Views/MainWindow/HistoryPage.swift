import AppKit
import SwiftUI

/// Saved transcripts to search, copy, and delete, and what history keeps.
struct HistoryPage: View {
    @AppStorage(AppSettingKey.historyEnabled) private var historyEnabled = true
    @AppStorage(AppSettingKey.historyKeepsAudio) private var historyKeepsAudio = false
    @AppStorage(AppSettingKey.historyRetention) private var historyRetentionRaw = HistoryRetention.defaultValue.rawValue

    @State private var model = DictationHistoryModel.shared
    @State private var searchText = ""
    @State private var selection: DictationHistoryEntry.ID?
    /// A shorter retention that would delete entries, awaiting confirmation.
    @State private var pendingRetention: HistoryRetention?
    @State private var isConfirmingClear = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            settingsBar
            Divider()
            content
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search transcripts")
        .toolbar {
            ToolbarItem {
                Button("Clear History…", systemImage: "trash", role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(model.entries.isEmpty)
                .help("Delete all saved transcripts and recordings")
            }
        }
        .confirmationDialog(
            "Delete all \(model.entries.count) saved transcripts?",
            isPresented: $isConfirmingClear
        ) {
            Button("Delete All", role: .destructive) {
                perform { try await model.deleteAll() }
            }
        } message: {
            Text("Saved recordings are deleted too. This can't be undone.")
        }
        .confirmationDialog(
            retentionConfirmationTitle,
            isPresented: Binding(
                get: { pendingRetention != nil },
                set: {
                    if !$0 {
                        pendingRetention = nil
                    }
                }
            ),
            presenting: pendingRetention
        ) { retention in
            Button("Delete Older Transcripts", role: .destructive) {
                applyRetention(retention)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert(
            "History Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            model.reload()
            expire(with: retention)
        }
    }

    // MARK: - Settings

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 20) {
                Toggle("Save transcripts", isOn: $historyEnabled)

                Picker("Keep for", selection: retentionBinding) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
                .fixedSize()
                .disabled(!historyEnabled)

                Toggle("Keep audio recordings", isOn: $historyKeepsAudio)
                    .disabled(!historyEnabled)
            }

            Text(settingsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsCaption: String {
        guard historyEnabled else {
            return "New dictations aren't saved. Saved transcripts stay until they expire or you delete them."
        }
        let location = "Saved only on this Mac and left out of backups."
        guard historyKeepsAudio else { return location }
        let budget = ByteCountFormatter.string(fromByteCount: DictationHistoryStore.defaultMaxAudioByteCount, countStyle: .file)
        return "\(location) Audio keeps the newest \(DictationHistoryStore.defaultMaxAudioEntryCount) recordings, up to \(budget)."
    }

    private var retention: HistoryRetention {
        HistoryRetention(rawValue: historyRetentionRaw) ?? .defaultValue
    }

    /// Shortening retention deletes entries, so it asks first when it would.
    private var retentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { retention },
            set: { newValue in
                if HistoryListing.expiringCount(model.entries, retention: newValue, now: Date()) > 0 {
                    pendingRetention = newValue
                } else {
                    applyRetention(newValue)
                }
            }
        )
    }

    private var retentionConfirmationTitle: String {
        guard let pendingRetention else { return "" }
        let count = HistoryListing.expiringCount(model.entries, retention: pendingRetention, now: Date())
        let noun = count == 1 ? "transcript" : "transcripts"
        return "Delete \(count) \(noun) older than \(pendingRetention.displayName.lowercased())?"
    }

    private func applyRetention(_ newValue: HistoryRetention) {
        historyRetentionRaw = newValue.rawValue
        pendingRetention = nil
        expire(with: newValue)
    }

    private func expire(with retention: HistoryRetention) {
        perform { try await model.applyRetention(retention) }
    }

    // MARK: - Entries

    @ViewBuilder
    private var content: some View {
        let matches = HistoryListing.filter(model.entries, query: searchText)
        if model.entries.isEmpty {
            emptyState
        } else if matches.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(selection: $selection) {
                ForEach(HistoryListing.sections(matches, now: Date(), calendar: .current, locale: .current)) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            HistoryRow(entry: entry, isExpanded: selection == entry.id) {
                                copy(entry.transcript)
                            }
                            .tag(entry.id)
                            .contextMenu {
                                contextMenu(for: entry)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .onCopyCommand {
                guard let entry = selectedEntry else { return [] }
                return [NSItemProvider(object: entry.transcript as NSString)]
            }
            .onDeleteCommand {
                if let entry = selectedEntry {
                    delete(entry)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if historyEnabled {
            ContentUnavailableView(
                "No Dictations Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Your transcripts appear here after you dictate.")
            )
        } else {
            ContentUnavailableView {
                Label("History Is Off", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Turn it on to keep your transcripts on this Mac.")
            } actions: {
                Button("Turn On History") {
                    historyEnabled = true
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: DictationHistoryEntry) -> some View {
        Button("Copy") {
            copy(entry.transcript)
        }
        if let original = HistoryListing.originalTranscript(of: entry) {
            Button("Copy Original") {
                copy(original)
            }
        }
        if entry.hasAudio {
            Button("Play Recording") {
                openRecording(of: entry) { NSWorkspace.shared.open($0) }
            }
            Button("Show Recording in Finder") {
                openRecording(of: entry) { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            delete(entry)
        }
    }

    private var selectedEntry: DictationHistoryEntry? {
        model.entries.first { $0.id == selection }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
    }

    private func delete(_ entry: DictationHistoryEntry) {
        perform { try await model.delete(entry) }
    }

    private func openRecording(of entry: DictationHistoryEntry, _ open: (URL) -> Void) {
        guard let url = model.audioURL(for: entry), FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The recording for this dictation is missing."
            return
        }
        open(url)
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// One saved dictation. Selecting it shows the whole transcript and, when
/// cleanup changed it, the original.
private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    let isExpanded: Bool
    let onCopy: () -> Void

    @State private var didCopy = false
    @State private var showsOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = entry.appBundleID.flatMap(AppIconCache.icon(forBundleID:)) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }

                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: copy) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
                .accessibilityLabel(didCopy ? "Copied" : "Copy")
            }

            if transcript.isEmpty {
                Text("No text")
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                Text(transcript)
                    .lineLimit(isExpanded ? nil : 3)
            }

            if isExpanded, let original = HistoryListing.originalTranscript(of: entry) {
                DisclosureGroup("Original", isExpanded: $showsOriginal) {
                    Text(original)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var transcript: String {
        entry.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var details: String {
        var parts = [entry.timestamp.formatted(date: .omitted, time: .shortened)]
        if let appName = entry.appName {
            parts.append(appName)
        }
        parts.append(Duration.seconds(entry.duration).formatted(.time(pattern: .minuteSecond)))
        if entry.hasAudio {
            parts.append("Recording")
        }
        return parts.joined(separator: " · ")
    }

    private func copy() {
        onCopy()
        didCopy = true
        Task {
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            didCopy = false
        }
    }
}

/// App icons by bundle ID, looked up once per app.
@MainActor
private enum AppIconCache {
    private static var icons: [String: NSImage?] = [:]

    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] {
            return cached
        }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = icon
        return icon
    }
}
