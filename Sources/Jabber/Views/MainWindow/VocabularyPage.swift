import SwiftUI

/// Custom vocabulary prompt to bias transcription toward specific terms.
struct VocabularyPage: View {
    @AppStorage(AppSettingKey.vocabularyPrompt) private var vocabularyPrompt = ""

    var body: some View {
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
