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

    private let repoName = "argmaxinc/whisperkit-coreml"

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
        guard let idx = models.firstIndex(where: { $0.id == modelId }) else { return }

        models[idx].isDownloading = true
        models[idx].downloadProgress = 0

        defer {
            models[idx].isDownloading = false
        }

        _ = try await WhisperKit.download(
            variant: modelId,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    guard let self,
                          let idx = self.models.firstIndex(where: { $0.id == modelId }) else { return }
                    self.models[idx].downloadProgress = progress.fractionCompleted
                }
            }
        )

        models[idx].isDownloaded = true
        models[idx].downloadProgress = 1.0
    }

    func deleteModel(_ modelId: String) throws {
        let currentModel = UserDefaults.standard.string(forKey: "selectedModel")

        // Prevent deleting currently selected model if it's the only one
        if currentModel == modelId && downloadedModels.count == 1 {
            throw ModelError.cannotDeleteActiveModel
        }

        guard let modelPath = modelFolderPath(for: modelId) else { return }

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return
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

    private func modelsBaseURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent(repoName)
    }

    private func modelFolderPath(for modelId: String) -> URL? {
        guard let base = modelsBaseURL() else { return nil }

        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return nil }

        guard let contents = try? fm.contentsOfDirectory(atPath: base.path) else {
            return nil
        }

        let suffixPattern = "-\(modelId)"

        for folder in contents {
            let matchesExactSuffix = folder.hasSuffix(suffixPattern)
            let matchesExactName = folder == modelId

            guard matchesExactSuffix || matchesExactName else {
                continue
            }

            let folderURL = base.appendingPathComponent(folder)
            let configPath = folderURL.appendingPathComponent("config.json")

            guard fm.fileExists(atPath: configPath.path) else {
                continue
            }

            return folderURL
        }

        return nil
    }

    private func installedModelIds() -> [String] {
        guard let base = modelsBaseURL() else { return [] }

        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(atPath: base.path) else {
            return []
        }

        return modelDefinitions.compactMap { def in
            let suffixPattern = "-\(def.id)"

            let matchesAny = contents.contains { folder in
                let matchesExactSuffix = folder.hasSuffix(suffixPattern)
                let matchesExactName = folder == def.id

                guard matchesExactSuffix || matchesExactName else {
                    return false
                }

                let folderURL = base.appendingPathComponent(folder)
                let configPath = folderURL.appendingPathComponent("config.json")
                return fm.fileExists(atPath: configPath.path)
            }

            return matchesAny ? def.id : nil
        }
    }
}

enum ModelError: Error, LocalizedError {
    case cannotDeleteActiveModel

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveModel:
            return "Cannot delete the currently active model. Please select a different model first."
        }
    }
}
