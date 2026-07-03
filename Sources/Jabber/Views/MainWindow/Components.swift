import AppKit
import SwiftUI

// Shared controls used by the main window pages and the menu bar popover.

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

/// Renders a hotkey as individual keycaps, e.g. [⌥] [Space].
struct KeycapsView: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, label.count > 1 ? 8 : 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
                    )
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
    let onCancelDownload: () -> Void

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

        Button("Cancel") {
            onCancelDownload()
        }
        .buttonStyle(.borderless)
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

struct HistoryEntryRow: View {
    let entry: DictationHistoryEntry
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .fontWeight(.semibold)

                Text(entry.transcript.isEmpty ? "No transcript text" : entry.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("\(entry.modelName) • \(entry.languageDisplayName) • \(entry.durationDisplayText) • \(entry.audioSizeDisplayText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Reveal") {
                onReveal()
            }
            .buttonStyle(.borderless)
        }
    }
}

private extension DictationHistoryEntry {
    var durationDisplayText: String {
        String(format: "%.1fs", duration)
    }

    var audioSizeDisplayText: String {
        ByteCountFormatter.string(fromByteCount: audioByteCount, countStyle: .file)
    }

    var languageDisplayName: String {
        if language == "auto" {
            return "Auto"
        }
        return Constants.sortedLanguages.first { $0.code == language }?.name ?? language
    }
}
