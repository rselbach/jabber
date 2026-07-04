import SwiftUI

/// App info, model attributions, and library licenses.
struct AboutPage: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jabber")
                            .font(.headline)
                        Text("Version \(AppVersion.displayString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Local speech-to-text for macOS. Audio is processed on-device; optional transcript refinement can use a cloud provider.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }

            Section {
                ForEach(AppMode.modelDefinitions) { def in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(def.name)
                            .font(.body)
                        Text(def.attribution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let url = URL(string: def.licenseUrl) {
                            Link(def.license, destination: url)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Models")
            }

            Section {
                Link("speech-swift — Apache 2.0", destination: URL(string: "https://github.com/soniqo/speech-swift")!)
                Link("Sparkle — MIT", destination: URL(string: "https://sparkle-project.org/")!)
            } header: {
                Text("Libraries")
            }
        }
        .formStyle(.grouped)
    }
}
