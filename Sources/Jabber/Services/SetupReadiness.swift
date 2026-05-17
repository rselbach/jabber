import Foundation

enum SetupStepID: String, CaseIterable, Equatable, Sendable {
    case microphone
    case accessibility
    case model
}

enum SetupStepStatus: String, Equatable, Sendable {
    case complete
    case needsAction
    case inProgress
}

enum SetupStepAction: Equatable, Sendable {
    case requestMicrophone
    case openAccessibilitySettings
    case downloadBaseModel
}

struct SetupStep: Identifiable, Equatable, Sendable {
    let id: SetupStepID
    let title: String
    let message: String
    let status: SetupStepStatus
    let actionTitle: String?
    let action: SetupStepAction?
}

struct SetupReadiness: Equatable, Sendable {
    let steps: [SetupStep]

    var isComplete: Bool {
        steps.allSatisfy { $0.status == .complete }
    }

    var requiredSteps: [SetupStep] {
        steps.filter { $0.status != .complete }
    }
}

enum SetupReadinessResolver {
    static func resolve(
        hasMicrophonePermission: Bool,
        hasAccessibilityPermission: Bool,
        requiresAccessibilityPermission: Bool,
        hasDownloadedModel: Bool,
        isDownloadingModel: Bool
    ) -> SetupReadiness {
        SetupReadiness(steps: [
            microphoneStep(hasPermission: hasMicrophonePermission),
            accessibilityStep(
                hasPermission: hasAccessibilityPermission,
                isRequired: requiresAccessibilityPermission
            ),
            modelStep(
                hasDownloadedModel: hasDownloadedModel,
                isDownloadingModel: isDownloadingModel
            )
        ])
    }

    private static func microphoneStep(hasPermission: Bool) -> SetupStep {
        guard !hasPermission else {
            return SetupStep(
                id: .microphone,
                title: "Microphone",
                message: "Jabber can record audio for dictation.",
                status: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        return SetupStep(
            id: .microphone,
            title: "Microphone",
            message: "Allow microphone access so Jabber can record speech.",
            status: .needsAction,
            actionTitle: "Grant Access",
            action: .requestMicrophone
        )
    }

    private static func accessibilityStep(
        hasPermission: Bool,
        isRequired: Bool
    ) -> SetupStep {
        guard isRequired else {
            return SetupStep(
                id: .accessibility,
                title: "Accessibility",
                message: "Not required while output is set to copy to clipboard.",
                status: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        guard !hasPermission else {
            return SetupStep(
                id: .accessibility,
                title: "Accessibility",
                message: "Jabber can paste transcriptions into the active app.",
                status: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        return SetupStep(
            id: .accessibility,
            title: "Accessibility",
            message: "Allow Accessibility so paste mode can type into other apps.",
            status: .needsAction,
            actionTitle: "Open Settings",
            action: .openAccessibilitySettings
        )
    }

    private static func modelStep(
        hasDownloadedModel: Bool,
        isDownloadingModel: Bool
    ) -> SetupStep {
        if hasDownloadedModel {
            return SetupStep(
                id: .model,
                title: "Speech Model",
                message: "A local transcription model is installed.",
                status: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        if isDownloadingModel {
            return SetupStep(
                id: .model,
                title: "Speech Model",
                message: "Jabber is downloading a local transcription model.",
                status: .inProgress,
                actionTitle: nil,
                action: nil
            )
        }

        return SetupStep(
            id: .model,
            title: "Speech Model",
            message: "Download a local model before dictating.",
            status: .needsAction,
            actionTitle: "Download Base Model",
            action: .downloadBaseModel
        )
    }
}
