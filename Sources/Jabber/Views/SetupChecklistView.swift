import SwiftUI

struct SetupChecklistView: View {
    let readiness: SetupReadiness
    let showsCompleteMessage: Bool
    let onRequestMicrophone: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onDownloadBaseModel: () -> Void

    init(
        readiness: SetupReadiness,
        showsCompleteMessage: Bool = true,
        onRequestMicrophone: @escaping () -> Void,
        onOpenAccessibilitySettings: @escaping () -> Void,
        onDownloadBaseModel: @escaping () -> Void
    ) {
        self.readiness = readiness
        self.showsCompleteMessage = showsCompleteMessage
        self.onRequestMicrophone = onRequestMicrophone
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onDownloadBaseModel = onDownloadBaseModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCompleteMessage && readiness.isComplete {
                Label("Jabber is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            ForEach(readiness.steps) { step in
                SetupStepRow(step: step) {
                    perform(step.action)
                }
            }
        }
    }

    private func perform(_ action: SetupStepAction?) {
        guard let action else { return }
        switch action {
        case .requestMicrophone:
            onRequestMicrophone()
        case .openAccessibilitySettings:
            onOpenAccessibilitySettings()
        case .downloadBaseModel:
            onDownloadBaseModel()
        }
    }
}

private struct SetupStepRow: View {
    let step: SetupStep
    let performAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(step.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = step.actionTitle,
                   step.status == .needsAction {
                    Button(actionTitle) {
                        performAction()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var iconName: String {
        switch step.status {
        case .complete:
            return "checkmark.circle.fill"
        case .needsAction:
            return "exclamationmark.circle.fill"
        case .inProgress:
            return "arrow.down.circle.fill"
        }
    }

    private var iconColor: Color {
        switch step.status {
        case .complete:
            return .green
        case .needsAction:
            return .orange
        case .inProgress:
            return .blue
        }
    }
}
