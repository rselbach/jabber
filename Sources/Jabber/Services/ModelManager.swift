import Foundation
import AudioCommon
import os

struct ModelDownloadState: Equatable {
    enum Phase: String, Equatable {
        case started
        case progress
        case finished
        case failed
    }

    let modelId: String
    let progress: Double
    let status: String
    let phase: Phase
    let errorDescription: String?
    let isCancelled: Bool
}

@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "ModelManager")
    private static let downloadWaitTimeout: Duration = .seconds(600)
    private static let legacyModelIdMigration: [String: String] = [
        "tiny": AppMode.baseModelId,
        "small": AppMode.baseModelId,
        "large-v3": AppMode.largeModelId,
        "qwen3-asr-0.6b-mlx-4bit": AppMode.baseModelId,
        "qwen3-asr-1.7b-mlx-4bit": AppMode.mediumModelId,
        "qwen3-asr-1.7b-mlx-8bit": AppMode.largeModelId
    ]

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
    private var lastDownloadProgressReport: [String: CFAbsoluteTime] = [:]
    private let downloadProgressReportInterval: TimeInterval = 0.1

    private struct ModelDefinition {
        let id: String
        let name: String
        let description: String
        let sizeHint: String
    }

    private func updateModel(_ modelId: String, update: (inout Model) -> Void) {
        guard let index = models.firstIndex(where: { $0.id == modelId }) else { return }
        update(&models[index])
    }

    private let modelDefinitions: [ModelDefinition] = AppMode.qwen3ASRVariants.map {
        .init(
            id: $0.modelId,
            name: $0.name,
            description: $0.description,
            sizeHint: $0.sizeHint
        )
    }

    private init() {
        migrateSelectedModelIfNeeded()
        refreshModels()
    }

    var downloadedModels: [Model] {
        models.filter { $0.isDownloaded }
    }

    var hasAnyDownloadedModel: Bool {
        !downloadedModels.isEmpty
    }

    func selectedModelId() -> String {
        migrateSelectedModelIfNeeded()
        return AppSettings.string(AppSettingKey.selectedModel, default: AppMode.baseModelId)
    }

    @discardableResult
    func migrateSelectedModelIfNeeded(notify: Bool = false) -> Bool {
        let current = AppSettings.string(AppSettingKey.selectedModel, default: AppMode.baseModelId)
        let migrated: String

        if let legacyReplacement = Self.legacyModelIdMigration[current] {
            migrated = legacyReplacement
        } else if Self.isQwen3ASRModel(current) {
            return false
        } else {
            migrated = AppMode.baseModelId
        }

        guard migrated != current else { return false }

        logger.info("Migrating selected model from '\(current)' to '\(migrated)'")
        AppSettings.setString(migrated, forKey: AppSettingKey.selectedModel)
        if notify {
            NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        }
        return true
    }

    func refreshModels() {
        migrateSelectedModelIfNeeded()
        let downloadedIds = Set(installedModelIds())
        let existingById = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        models = modelDefinitions.map { def in
            let wasDownloading = existingById[def.id]?.isDownloading ?? false
            let previousProgress = existingById[def.id]?.downloadProgress ?? 0
            let isDownloaded = downloadedIds.contains(def.id)
            return Model(
                id: def.id,
                name: def.name,
                description: def.description,
                sizeHint: def.sizeHint,
                isDownloaded: isDownloaded,
                isDownloading: !isDownloaded && wasDownloading,
                downloadProgress: isDownloaded ? 1.0 : previousProgress
            )
        }
    }

    func selectModel(_ modelId: String, previousModelId: String?) -> Bool {
        guard downloadedModels.contains(where: { $0.id == modelId }) else { return false }
        let current = previousModelId ?? AppSettings.string(AppSettingKey.selectedModel, default: AppMode.baseModelId)
        guard current != modelId else { return false }
        AppSettings.setString(modelId, forKey: AppSettingKey.selectedModel)
        NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        return true
    }

    func ensureModelDownloaded(_ modelId: String) async throws -> URL {
        if let existing = qwen3ASRModelFolder(for: modelId) {
            return existing
        }
        return try await downloadModel(modelId)
    }

    @discardableResult
    func downloadModel(_ modelId: String) async throws -> URL {
        // Verify model exists before starting
        guard models.contains(where: { $0.id == modelId }) else {
            logger.warning("Attempted to download non-existent model: \(modelId)")
            throw ModelError.modelNotFound(modelId: modelId)
        }

        if let existing = localModelFolder(for: modelId) {
            updateModel(modelId) { model in
                model.isDownloaded = true
                model.isDownloading = false
                model.downloadProgress = 1.0
            }
            return existing
        }

        // Set initial download state
        guard let idx = models.firstIndex(where: { $0.id == modelId }) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        if models[idx].isDownloading {
            try await waitForDownloadToFinish(modelId: modelId)
            if let existing = localModelFolder(for: modelId) {
                return existing
            }
            throw ModelError.modelNotFound(modelId: modelId)
        }

        let modelName = models[idx].name
        models[idx].isDownloading = true
        models[idx].downloadProgress = 0

        postDownloadState(
            modelId: modelId,
            modelName: modelName,
            progress: 0,
            phase: .started
        )

        defer {
            lastDownloadProgressReport[modelId] = nil
            // Always clear downloading state, even on error
            updateModel(modelId) { model in
                model.isDownloading = false
            }
        }

        let modelFolder: URL
        do {
            modelFolder = try await downloadQwen3ASRModel(modelId: modelId, modelName: modelName)
        } catch is CancellationError {
            postDownloadState(
                modelId: modelId,
                modelName: modelName,
                progress: models[idx].downloadProgress,
                phase: .failed,
                isCancelled: true
            )
            throw CancellationError()
        } catch {
            postDownloadState(
                modelId: modelId,
                modelName: modelName,
                progress: models[idx].downloadProgress,
                phase: .failed,
                errorDescription: error.localizedDescription
            )
            throw error
        }

        // Look up index after download completes
        updateModel(modelId) { model in
            model.isDownloaded = true
            model.downloadProgress = 1.0
        }

        postDownloadState(
            modelId: modelId,
            modelName: modelName,
            progress: 1.0,
            phase: .finished
        )

        return modelFolder
    }

    func deleteModel(_ modelId: String) throws {
        let currentModel = AppSettings.string(AppSettingKey.selectedModel, default: AppMode.baseModelId)

        // Prevent deleting currently selected model if it's the only one
        if currentModel == modelId && downloadedModels.count == 1 {
            throw ModelError.cannotDeleteActiveModel
        }

        guard let modelPath = localModelFolder(for: modelId) else {
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
                AppSettings.setString(AppMode.baseModelId, forKey: AppSettingKey.selectedModel)
                return
            }
            AppSettings.setString(firstDownloaded, forKey: AppSettingKey.selectedModel)
            NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        }
    }

    func ensureDefaultModelDownloaded() async {
        if hasAnyDownloadedModel { return }

        do {
            try await downloadModel(AppMode.baseModelId)
            AppSettings.setString(AppMode.baseModelId, forKey: AppSettingKey.selectedModel)
        } catch {
            logger.error("Failed to download base model: \(error.localizedDescription)")
        }
    }

    private func installedModelIds() -> [String] {
        return modelDefinitions.compactMap { def in
            localModelFolder(for: def.id) != nil ? def.id : nil
        }
    }

    nonisolated static func isQwen3ASRModel(_ modelId: String) -> Bool {
        AppMode.qwen3ASRVariant(for: modelId) != nil
    }

    nonisolated static func qwen3ASRHuggingFaceModelId(for modelId: String) -> String? {
        AppMode.qwen3ASRVariant(for: modelId)?.huggingFaceModelId
    }

    func isQwen3ASRModel(_ modelId: String) -> Bool {
        Self.isQwen3ASRModel(modelId)
    }

    private func localModelFolder(for modelId: String) -> URL? {
        qwen3ASRModelFolder(for: modelId)
    }

    private func downloadQwen3ASRModel(modelId: String, modelName: String) async throws -> URL {
        guard let huggingFaceModelId = Self.qwen3ASRHuggingFaceModelId(for: modelId) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        let modelFolder = try HuggingFaceDownloader.getCacheDirectory(for: huggingFaceModelId)

        try await HuggingFaceDownloader.downloadWeights(
            modelId: huggingFaceModelId,
            to: modelFolder,
            additionalFiles: ["vocab.json", "merges.txt", "tokenizer_config.json"],
            progressHandler: { [weak self] progress in
                Task { @MainActor in
                    self?.publishDownloadProgress(
                        modelId: modelId,
                        modelName: modelName,
                        progress: progress,
                        status: "Downloading weights..."
                    )
                }
            }
        )
        return modelFolder
    }

    private func qwen3ASRModelFolder(for modelId: String) -> URL? {
        guard let huggingFaceModelId = Self.qwen3ASRHuggingFaceModelId(for: modelId) else {
            return nil
        }

        let fm = FileManager.default
        let candidates = [
            qwen3ASRCacheFolder(for: huggingFaceModelId),
            qwen3ASROldCacheFolder(for: huggingFaceModelId)
        ]
        return candidates.first { folder in
            guard fm.fileExists(atPath: folder.path) else { return false }
            guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                return false
            }
            return contents.contains { $0.pathExtension == "safetensors" }
        }
    }

    private func qwen3ASRCacheFolder(for huggingFaceModelId: String) -> URL {
        let components = huggingFaceModelId.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return qwen3ASROldCacheFolder(for: huggingFaceModelId)
        }

        return qwen3ASRCacheBase()
            .appendingPathComponent("models")
            .appendingPathComponent(components[0])
            .appendingPathComponent(components[1])
    }

    private func qwen3ASROldCacheFolder(for huggingFaceModelId: String) -> URL {
        qwen3ASRCacheBase()
            .appendingPathComponent(HuggingFaceDownloader.sanitizedCacheKey(for: huggingFaceModelId))
    }

    private func qwen3ASRCacheBase() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["QWEN3_CACHE_DIR"] ?? environment["QWEN3_ASR_CACHE_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("qwen3-speech", isDirectory: true)
        }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("qwen3-speech", isDirectory: true)
    }

    private func publishDownloadProgress(
        modelId: String,
        modelName: String,
        progress: Double,
        status: String? = nil
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard shouldPublishDownloadProgress(modelId: modelId, progress: progress, now: now) else { return }

        updateModel(modelId) { model in
            model.downloadProgress = progress
        }
        postDownloadState(
            modelId: modelId,
            modelName: modelName,
            progress: progress,
            phase: .progress,
            statusOverride: status
        )
    }

    private func waitForDownloadToFinish(modelId: String) async throws {
        let startTime = ContinuousClock.now
        while let idx = models.firstIndex(where: { $0.id == modelId }) {
            try Task.checkCancellation()
            guard models[idx].isDownloading else { return }
            if ContinuousClock.now - startTime > Self.downloadWaitTimeout {
                throw ModelError.downloadTimeout(modelId: modelId)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ModelError.modelNotFound(modelId: modelId)
    }

    private func postDownloadState(
        modelId: String,
        modelName: String,
        progress: Double,
        phase: ModelDownloadState.Phase,
        statusOverride: String? = nil,
        errorDescription: String? = nil,
        isCancelled: Bool = false
    ) {
        let status = statusOverride ?? downloadStatus(
            modelName: modelName,
            progress: progress,
            phase: phase,
            isCancelled: isCancelled
        )
        NotificationCenter.default.post(
            name: Constants.Notifications.modelDownloadStateDidChange,
            object: ModelDownloadState(
                modelId: modelId,
                progress: progress,
                status: status,
                phase: phase,
                errorDescription: errorDescription,
                isCancelled: isCancelled
            )
        )
    }

    private func shouldPublishDownloadProgress(
        modelId: String,
        progress: Double,
        now: CFAbsoluteTime
    ) -> Bool {
        guard progress < 1.0 else {
            lastDownloadProgressReport[modelId] = 0
            return true
        }

        let lastReport = lastDownloadProgressReport[modelId] ?? 0
        guard now - lastReport >= downloadProgressReportInterval else { return false }

        lastDownloadProgressReport[modelId] = now
        return true
    }

    private func downloadStatus(
        modelName: String,
        progress: Double,
        phase: ModelDownloadState.Phase,
        isCancelled: Bool
    ) -> String {
        switch phase {
        case .started, .progress:
            return "Downloading \(modelName)... \(Int(progress * 100))%"
        case .finished:
            return "Downloaded \(modelName)"
        case .failed:
            if isCancelled {
                return "Download cancelled: \(modelName)"
            }
            return "Download failed: \(modelName)"
        }
    }
}

enum ModelError: Error, LocalizedError {
    case cannotDeleteActiveModel
    case downloadTimeout(modelId: String)
    case modelNotFound(modelId: String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveModel:
            return "Cannot delete the currently active model. Please select a different model first."
        case .downloadTimeout(let modelId):
            return "Download timed out for model '\(modelId)'."
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found or already deleted."
        }
    }
}
