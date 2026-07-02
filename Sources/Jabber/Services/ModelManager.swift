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
    private static let legacyModelIdMigration: [String: String] = [
        "tiny": AppMode.qwen3Small4BitModelId,
        "small": AppMode.qwen3Small4BitModelId,
        "large-v3": AppMode.qwen3ModelId,
        "base": AppMode.qwen3Small4BitModelId,
        "medium": AppMode.qwen3Large4BitModelId,
        "large": AppMode.qwen3ModelId,
        "qwen3-asr-0.6b-mlx-4bit": AppMode.qwen3Small4BitModelId,
        "qwen3-asr-0.6b-mlx-8bit": AppMode.qwen3Small8BitModelId,
        "qwen3-asr-1.7b-mlx-4bit": AppMode.qwen3Large4BitModelId,
        "qwen3-asr-1.7b-mlx-8bit": AppMode.qwen3ModelId
    ]

    struct Model: Identifiable {
        let id: String
        let name: String
        let description: String
        let sizeHint: String
        let family: AppMode.ModelFamily
        var isDownloaded: Bool
        var isDownloading: Bool
        var downloadProgress: Double
    }

    private(set) var models: [Model] = []
    private var lastDownloadProgressReport: [String: CFAbsoluteTime] = [:]
    private var activeDownloads: [String: ActiveDownload] = [:]
    private let downloadProgressReportInterval: TimeInterval = 0.1
    private let settings: SettingsStore
    private let cacheBaseURL: URL?

    private struct ActiveDownload {
        let id: UUID
        let task: Task<URL, Error>
    }

    private func updateModel(_ modelId: String, update: (inout Model) -> Void) {
        guard let index = models.firstIndex(where: { $0.id == modelId }) else { return }
        update(&models[index])
    }

    private let modelDefinitions: [AppMode.ModelDefinition] = AppMode.modelDefinitions

    init(
        settings: SettingsStore = .standard,
        cacheBaseURL: URL? = nil
    ) {
        self.settings = settings
        self.cacheBaseURL = cacheBaseURL
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
        return settings[.selectedModel]
    }

    @discardableResult
    func migrateSelectedModelIfNeeded(notify: Bool = false) -> Bool {
        let current = settings[.selectedModel]

        if let legacyReplacement = Self.legacyModelIdMigration[current] {
            guard legacyReplacement != current else { return false }
            logger.info("Migrating selected model from '\(current)' to '\(legacyReplacement)'")
            settings[.selectedModel] = legacyReplacement
            if notify {
                NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
            }
            return true
        }

        guard AppMode.modelDefinition(for: current) == nil else { return false }

        let fallback = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
        logger.info("Migrating selected model from '\(current)' to '\(fallback)'")
        settings[.selectedModel] = fallback
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
                family: def.family,
                isDownloaded: isDownloaded,
                isDownloading: !isDownloaded && wasDownloading,
                downloadProgress: isDownloaded ? 1.0 : previousProgress
            )
        }
    }

    func selectModel(_ modelId: String) -> Bool {
        guard downloadedModels.contains(where: { $0.id == modelId }) else { return false }
        guard settings[.selectedModel] != modelId else { return false }
        settings[.selectedModel] = modelId
        NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        return true
    }

    func ensureModelDownloaded(_ modelId: String) async throws -> URL {
        if let def = AppMode.modelDefinition(for: modelId), def.isBuiltIn {
            updateModel(modelId) { model in
                model.isDownloaded = true
                model.isDownloading = false
                model.downloadProgress = 1.0
            }
            return cacheBase()
        }

        if let existing = modelFolder(for: modelId) {
            updateModel(modelId) { model in
                model.isDownloaded = true
                model.isDownloading = false
                model.downloadProgress = 1.0
            }
            return existing
        }
        return try await downloadModel(modelId)
    }

    @discardableResult
    func startDownload(_ modelId: String) -> Bool {
        guard models.contains(where: { $0.id == modelId }) else {
            logger.warning("Attempted to start download for non-existent model: \(modelId)")
            return false
        }

        guard activeDownloads[modelId] == nil else { return false }

        _ = ensureActiveDownloadTask(for: modelId)
        return true
    }

    func cancelDownload(_ modelId: String) {
        guard let activeDownload = activeDownloads[modelId] else { return }
        activeDownload.task.cancel()
    }

    private func clearActiveDownload(modelId: String, downloadID: UUID) {
        guard activeDownloads[modelId]?.id == downloadID else { return }
        activeDownloads[modelId] = nil
    }

    @discardableResult
    func downloadModel(_ modelId: String) async throws -> URL {
        guard models.contains(where: { $0.id == modelId }) else {
            logger.warning("Attempted to download non-existent model: \(modelId)")
            throw ModelError.modelNotFound(modelId: modelId)
        }

        if let existing = modelFolder(for: modelId) {
            updateModel(modelId) { model in
                model.isDownloaded = true
                model.isDownloading = false
                model.downloadProgress = 1.0
            }
            return existing
        }

        let task = ensureActiveDownloadTask(for: modelId)
        return try await task.value
    }

    private func ensureActiveDownloadTask(for modelId: String) -> Task<URL, Error> {
        if let active = activeDownloads[modelId] {
            return active.task
        }

        let downloadID = UUID()
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.performDownload(modelId: modelId)
        }
        activeDownloads[modelId] = ActiveDownload(id: downloadID, task: task)

        Task { [weak self] in
            do {
                _ = try await task.value
            } catch is CancellationError {
            } catch {
                self?.logger.error("Model download failed for \(modelId): \(error.localizedDescription)")
            }
            self?.clearActiveDownload(modelId: modelId, downloadID: downloadID)
        }

        return task
    }

    private func performDownload(modelId: String) async throws -> URL {
        if let existing = modelFolder(for: modelId) {
            updateModel(modelId) { model in
                model.isDownloaded = true
                model.isDownloading = false
                model.downloadProgress = 1.0
            }
            return existing
        }

        guard let idx = models.firstIndex(where: { $0.id == modelId }) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        let modelName = models[idx].name

        updateModel(modelId) { model in
            model.isDownloading = true
            model.downloadProgress = 0
        }

        postDownloadState(
            modelId: modelId,
            modelName: modelName,
            progress: 0,
            phase: .started
        )

        defer {
            lastDownloadProgressReport[modelId] = nil
            updateModel(modelId) { model in
                model.isDownloading = false
            }
        }

        let modelFolder: URL
        do {
            modelFolder = try await downloadModelFiles(modelId: modelId, modelName: modelName)
        } catch is CancellationError {
            postDownloadState(
                modelId: modelId,
                modelName: modelName,
                progress: currentDownloadProgress(for: modelId),
                phase: .failed,
                isCancelled: true
            )
            // Preserve HuggingFace .incomplete resume data on user cancellation
            // so a re-download picks up where it left off — do NOT clean up.
            throw CancellationError()
        } catch {
            postDownloadState(
                modelId: modelId,
                modelName: modelName,
                progress: currentDownloadProgress(for: modelId),
                phase: .failed,
                errorDescription: error.localizedDescription
            )
            // Clean up the partial folder. HuggingFaceDownloader already retried
            // 3x internally, so a failure here is genuine (network/hard-fault/
            // incomplete validation); leftover config.json and partial .mlmodelc
            // contents would linger as invisible junk since modelFolder(for:)
            // returns nil for incomplete installs.
            removeFailedDownloadFolder(for: modelId)
            throw error
        }

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

    private func currentDownloadProgress(for modelId: String) -> Double {
        guard let model = models.first(where: { $0.id == modelId }) else { return 0 }
        return min(max(model.downloadProgress, 0), 1)
    }

    func deleteModel(_ modelId: String) throws {
        guard let def = AppMode.modelDefinition(for: modelId), !def.isBuiltIn else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        let currentModel = settings[.selectedModel]

        if currentModel == modelId, downloadedModels.count == 1 {
            throw ModelError.cannotDeleteActiveModel
        }

        guard let modelPath = modelFolder(for: modelId) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        try FileManager.default.removeItem(at: modelPath)

        let didSwitchSelection: Bool
        if currentModel == modelId {
            let fallback = downloadedModels.first(where: { $0.id != modelId })?.id
                ?? LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
            settings[.selectedModel] = fallback
            didSwitchSelection = true
        } else {
            didSwitchSelection = false
        }

        refreshModels()

        if didSwitchSelection {
            NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        }
    }

    private func installedModelIds() -> [String] {
        modelDefinitions.compactMap { def in
            if def.isBuiltIn { return def.id }
            return modelFolder(for: def.id) != nil ? def.id : nil
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

    private func modelFolder(for modelId: String) -> URL? {
        guard let def = AppMode.modelDefinition(for: modelId) else { return nil }

        let candidates = [
            cacheFolder(for: def.huggingFaceModelId),
            oldCacheFolder(for: def.huggingFaceModelId)
        ]

        for folder in candidates {
            let validation = ModelInstallationValidator.validate(folder: folder, for: def.family)
            guard validation.folderExists else { continue }
            if validation.isComplete {
                return folder
            }
            logger.warning("Ignoring incomplete model folder at \(folder.path): \(validation.failureDescription)")
        }

        return nil
    }

    /// Resolve the on-disk download folder for a model. Centralized so the
    /// download path and failure cleanup always agree on the location.
    private func downloadFolder(for modelId: String) throws -> URL {
        guard let def = AppMode.modelDefinition(for: modelId) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }
        return try HuggingFaceDownloader.getCacheDirectory(
            for: def.huggingFaceModelId,
            basePath: cacheBase()
        )
    }

    /// Remove a partially-downloaded model folder left behind by a failed
    /// download (partial config.json, half-written .mlmodelc, stale index).
    ///
    /// HuggingFace keeps its `.incomplete` resume data INSIDE this folder
    /// (at `<folder>/.cache/huggingface/download/*.incomplete`), so deleting
    /// it also discards resume state. Call this only on genuine failures,
    /// never on user cancellation — see `performDownload`.
    ///
    /// Logs cleanup and any removal error; never swallows failures silently.
    func removeFailedDownloadFolder(for modelId: String) {
        let folder: URL
        do {
            folder = try downloadFolder(for: modelId)
        } catch {
            logger.error("Could not resolve download folder for failed cleanup of \(modelId): \(error.localizedDescription)")
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }

        // Defensive: only delete a strict descendant of the cache base — never
        // the cache base itself, the shared `models` parent, or anything that
        // escapes the cache via path traversal.
        let cacheBasePath = cacheBase().standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        guard folderPath != cacheBasePath,
              folderPath.hasPrefix(cacheBasePath + "/"),
              folder.lastPathComponent != "models"
        else {
            logger.error("Refusing to delete unsafe path during cleanup of \(modelId): \(folderPath)")
            return
        }

        do {
            try fm.removeItem(at: folder)
            logger.info("Removed partial download folder for \(modelId) at \(folder.path)")
        } catch {
            logger.error("Failed to remove partial download folder for \(modelId) at \(folder.path): \(error.localizedDescription)")
        }
    }

    private func downloadModelFiles(modelId: String, modelName: String) async throws -> URL {
        guard let def = AppMode.modelDefinition(for: modelId) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        let downloadFolder = try downloadFolder(for: modelId)

        let additionalFiles: [String]
        switch def.family {
        case .qwen3ASR:
            additionalFiles = ["vocab.json", "merges.txt", "tokenizer_config.json"]
        case .nemotronASR:
            additionalFiles = [
                "encoder.mlmodelc/**",
                "decoder.mlmodelc/**",
                "joint.mlmodelc/**",
                "vocab.json"
            ]
        case .appleSpeech:
            throw ModelError.modelNotFound(modelId: modelId)
        }

        try await HuggingFaceDownloader.downloadWeights(
            modelId: def.huggingFaceModelId,
            to: downloadFolder,
            additionalFiles: additionalFiles,
            progressHandler: { @Sendable [weak self] progress in
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

        let validation = ModelInstallationValidator.validate(folder: downloadFolder, for: def.family)
        if validation.isComplete {
            return downloadFolder
        }

        if let verifiedFolder = modelFolder(for: modelId) {
            return verifiedFolder
        }

        throw ModelError.incompleteModelInstallation(
            modelId: modelId,
            details: validation.failureDescription
        )
    }

    private func cacheFolder(for huggingFaceModelId: String) -> URL {
        let components = huggingFaceModelId.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            return oldCacheFolder(for: huggingFaceModelId)
        }

        return cacheBase()
            .appendingPathComponent("models")
            .appendingPathComponent(components[0])
            .appendingPathComponent(components[1])
    }

    private func oldCacheFolder(for huggingFaceModelId: String) -> URL {
        cacheBase()
            .appendingPathComponent(HuggingFaceDownloader.sanitizedCacheKey(for: huggingFaceModelId))
    }

    private func cacheBase() -> URL {
        if let cacheBaseURL {
            return cacheBaseURL
        }

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
    case incompleteModelInstallation(modelId: String, details: String)
    case modelNotFound(modelId: String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveModel:
            return "Cannot delete the currently active model. Please select a different model first."
        case .downloadTimeout(let modelId):
            return "Download timed out for model '\(modelId)'."
        case .incompleteModelInstallation(let modelId, let details):
            return "Model '\(modelId)' is incomplete: \(details)."
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found or already deleted."
        }
    }
}
