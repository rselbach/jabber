import Foundation
import WhisperKit
import os

@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "ModelManager")

    struct Model: Identifiable {
        let id: String
        let name: String
        let description: String
        let sizeHint: String
        var isDownloaded: Bool
        var isDownloading: Bool
        var downloadProgress: Double
    }

    private(set) var models: [Model] = []

    private let modelDefinitions: [(id: String, name: String, description: String, sizeHint: String)] = [
        ("tiny", "Tiny", "Fastest, lowest accuracy", "~40MB"),
        ("base", "Base", "Balanced speed/accuracy", "~140MB"),
        ("small", "Small", "Good accuracy", "~460MB"),
        ("medium", "Medium", "Very accurate", "~1.5GB"),
        ("large-v3", "Large v3", "Best accuracy", "~3GB")
    ]

    private init() {
        refreshModels()
    }

    var downloadedModels: [Model] {
        models.filter { $0.isDownloaded }
    }

    var hasAnyDownloadedModel: Bool {
        !downloadedModels.isEmpty
    }

    func refreshModels() {
        let downloadedIds = Set(installedModelIds())
        models = modelDefinitions.map { def in
            Model(
                id: def.id,
                name: def.name,
                description: def.description,
                sizeHint: def.sizeHint,
                isDownloaded: downloadedIds.contains(def.id),
                isDownloading: false,
                downloadProgress: 0
            )
        }
    }

    func downloadModel(_ modelId: String) async throws {
        // Verify model exists before starting
        guard models.contains(where: { $0.id == modelId }) else {
            logger.warning("Attempted to download non-existent model: \(modelId)")
            return
        }

        // Set initial download state
        if let idx = models.firstIndex(where: { $0.id == modelId }) {
            models[idx].isDownloading = true
            models[idx].downloadProgress = 0
        }

        defer {
            // Always clear downloading state, even on error
            if let idx = models.firstIndex(where: { $0.id == modelId }) {
                models[idx].isDownloading = false
            }
        }

        _ = try await WhisperKit.download(
            variant: modelId,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    // Look up index each time to avoid stale references
                    if let idx = self.models.firstIndex(where: { $0.id == modelId }) {
                        self.models[idx].downloadProgress = progress.fractionCompleted
                    }
                }
            }
        )

        // Look up index after download completes
        if let idx = models.firstIndex(where: { $0.id == modelId }) {
            models[idx].isDownloaded = true
            models[idx].downloadProgress = 1.0
        }
    }

    func deleteModel(_ modelId: String) throws {
        let currentModel = UserDefaults.standard.string(forKey: "selectedModel")

        // Prevent deleting currently selected model if it's the only one
        if currentModel == modelId && downloadedModels.count == 1 {
            throw ModelError.cannotDeleteActiveModel
        }

        guard let modelPath = Constants.ModelPaths.localModelFolder(for: modelId) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        try FileManager.default.removeItem(at: modelPath)

        refreshModels()

        // Switch to another model if we deleted the selected one
        if currentModel == modelId {
            guard let firstDownloaded = downloadedModels.first?.id else {
                // This should never happen due to the guard at the top, but be safe
                logger.error("No models available after deletion, falling back to base")
                UserDefaults.standard.set("base", forKey: "selectedModel")
                return
            }
            UserDefaults.standard.set(firstDownloaded, forKey: "selectedModel")
            NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        }
    }

    func ensureDefaultModelDownloaded() async {
        if hasAnyDownloadedModel { return }

        do {
            try await downloadModel("base")
            UserDefaults.standard.set("base", forKey: "selectedModel")
        } catch {
            logger.error("Failed to download base model: \(error.localizedDescription)")
        }
    }

    private func installedModelIds() -> [String] {
        return modelDefinitions.compactMap { def in
            Constants.ModelPaths.localModelFolder(for: def.id) != nil ? def.id : nil
        }
    }
}

enum ModelError: Error, LocalizedError {
    case cannotDeleteActiveModel
    case modelNotFound(modelId: String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveModel:
            return "Cannot delete the currently active model. Please select a different model first."
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found or already deleted."
        }
    }
}
