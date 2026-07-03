import SwiftUI

/// Small one-time notice shown when a user's selected speech model was
/// removed in an update and silently migrated to a replacement that still
/// needs to be downloaded.
struct ModelMigrationNoticeView: View {
    let newModelName: String
    let onDownload: () -> Void
    let onChooseAnother: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Jabber was updated")
                        .font(.title2).fontWeight(.bold)
                    Text("Your previous speech model is no longer available, so we've switched you to **\(newModelName)**.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Not Now", action: onNotNow)
                    .keyboardShortcut(.escape)
                Button("Choose Another", action: onChooseAnother)
                Button("Download", action: onDownload)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
