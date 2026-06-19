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
    private var activeDownloads: [String: ActiveDownload] = [:]
    private let downloadProgressReportInterval: TimeInterval = 0.1
    private let settings: SettingsStore
    private let qwen3ASRCacheBaseURL: URL?

    private struct ActiveDownload {
        let id: UUID
        let task: Task<URL, Error>
    }

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

    init(
        settings: SettingsStore = .standard,
        qwen3ASRCacheBaseURL: URL? = nil
    ) {
        self.settings = settings
        self.qwen3ASRCacheBaseURL = qwen3ASRCacheBaseURL
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
        settings[.selectedModel] = migrated
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

    func selectModel(_ modelId: String) -> Bool {
        guard downloadedModels.contains(where: { $0.id == modelId }) else { return false }
        guard settings[.selectedModel] != modelId else { return false }
        settings[.selectedModel] = modelId
        NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        return true
    }

    func ensureModelDownloaded(_ modelId: String) async throws -> URL {
        if let existing = qwen3ASRModelFolder(for: modelId) {
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

        if let existing = localModelFolder(for: modelId) {
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
                // Cancellation state is published by performDownload.
            } catch {
                self?.logger.error("Model download failed for \(modelId): \(error.localizedDescription)")
            }
            self?.clearActiveDownload(modelId: modelId, downloadID: downloadID)
        }

        return task
    }

    private func performDownload(modelId: String) async throws -> URL {
        if let existing = localModelFolder(for: modelId) {
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
            modelFolder = try await downloadQwen3ASRModel(modelId: modelId, modelName: modelName)
        } catch is CancellationError {
            postDownloadState(
                modelId: modelId,
                modelName: modelName,
                progress: currentDownloadProgress(for: modelId),
                phase: .failed,
                isCancelled: true
            )
            throw CancellationError()
        } catch {
            postDownloadState(
                modelId: modelId,
                modelName: modelName,
                progress: currentDownloadProgress(for: modelId),
                phase: .failed,
                errorDescription: error.localizedDescription
            )
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
        let currentModel = settings[.selectedModel]

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

        // If we deleted the currently selected model, switch to another before
        // posting a single modelDidChange so the transcription service loads the
        // new selection instead of re-downloading the one we just deleted.
        let didSwitchSelection: Bool
        if currentModel == modelId {
            let fallback = downloadedModels.first(where: { $0.id != modelId })?.id
                ?? AppMode.baseModelId
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

        let downloadFolder = try HuggingFaceDownloader.getCacheDirectory(
            for: huggingFaceModelId,
            basePath: qwen3ASRCacheBase()
        )

        try await HuggingFaceDownloader.downloadWeights(
            modelId: huggingFaceModelId,
            to: downloadFolder,
            additionalFiles: ["vocab.json", "merges.txt", "tokenizer_config.json"],
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

        let validation = ModelInstallationValidator.validateQwen3ASRModelFolder(at: downloadFolder)
        if validation.isComplete {
            return downloadFolder
        }

        if let verifiedFolder = qwen3ASRModelFolder(for: modelId) {
            return verifiedFolder
        }

        throw ModelError.incompleteModelInstallation(
            modelId: modelId,
            details: validation.failureDescription
        )
    }

    private func qwen3ASRModelFolder(for modelId: String) -> URL? {
        guard let huggingFaceModelId = Self.qwen3ASRHuggingFaceModelId(for: modelId) else {
            return nil
        }

        let candidates = [
            qwen3ASRCacheFolder(for: huggingFaceModelId),
            qwen3ASROldCacheFolder(for: huggingFaceModelId)
        ]

        for folder in candidates {
            let validation = ModelInstallationValidator.validateQwen3ASRModelFolder(at: folder)
            guard validation.folderExists else { continue }
            if validation.isComplete {
                return folder
            }
            logger.warning("Ignoring incomplete model folder at \(folder.path): \(validation.failureDescription)")
        }

        return nil
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
        if let qwen3ASRCacheBaseURL {
            return qwen3ASRCacheBaseURL
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
