import XCTest
@testable import Jabber

@MainActor
final class ModelManagerTests: XCTestCase {
    private var modelManager: ModelManager!
    private var settings: SettingsStore!
    private var userDefaultsSuiteName: String!
    private var userDefaults: UserDefaults!
    private var cacheBaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        userDefaultsSuiteName = "JabberTests.ModelManager.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName))
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        settings = SettingsStore(userDefaults: userDefaults)

        cacheBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JabberModelManagerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheBaseURL,
            withIntermediateDirectories: true
        )

        settings[.selectedModel] = AppMode.parakeetUnifiedModelId
        modelManager = ModelManager(
            settings: settings,
            cacheBaseURL: cacheBaseURL
        )
    }

    override func tearDown() async throws {
        if let cacheBaseURL, FileManager.default.fileExists(atPath: cacheBaseURL.path) {
            try FileManager.default.removeItem(at: cacheBaseURL)
        }
        if let userDefaultsSuiteName, let userDefaults {
            userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        }
        modelManager = nil
        settings = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        cacheBaseURL = nil
        try await super.tearDown()
    }

    func testModelDefinitionsExist() {
        XCTAssertFalse(modelManager.models.isEmpty, "Should have model definitions")

        let modelIds = modelManager.models.map { $0.id }
        XCTAssertEqual(
            modelIds,
            [
                AppMode.parakeetModelId,
                AppMode.parakeetMultilingualModelId,
                AppMode.parakeetJapaneseModelId,
                AppMode.parakeetUnifiedModelId,
                AppMode.appleSpeechModelId
            ]
        )
    }

    func testRefreshModelsUsesInjectedCacheDirectory() throws {
        let modelFolder = fluidAudioFolder("parakeet-tdt-0.6b-v2")
        try createCompleteParakeetModelFolder(at: modelFolder)

        modelManager.refreshModels()

        let parakeetModel = try XCTUnwrap(
            modelManager.models.first { $0.id == AppMode.parakeetModelId }
        )
        XCTAssertTrue(parakeetModel.isDownloaded)
    }

    func testDeleteModelRemovesItsFolder() throws {
        let modelFolder = fluidAudioFolder("parakeet-tdt-0.6b-v2")
        try createCompleteParakeetModelFolder(at: modelFolder)
        modelManager.refreshModels()

        try modelManager.deleteModel(AppMode.parakeetModelId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelFolder.path))
        let parakeetModel = try XCTUnwrap(
            modelManager.models.first { $0.id == AppMode.parakeetModelId }
        )
        XCTAssertFalse(parakeetModel.isDownloaded)
    }

    func testLegacyDownloadsAreConsolidatedIntoFluidAudiosFolder() throws {
        let legacy = fluidAudioFolder("parakeet-tdt-0.6b-v2-coreml")
        let current = fluidAudioFolder("parakeet-tdt-0.6b-v2")
        let incomplete = { (url: URL) in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: url.appendingPathComponent("parakeet_vocab.json"))
        }
        let cases: [String: (legacy: (URL) throws -> Void, current: ((URL) throws -> Void)?, wantCurrentComplete: Bool)] = [
            "the only complete copy moves into place": (
                { try self.createCompleteParakeetModelFolder(at: $0) }, nil, true
            ),
            "a complete copy replaces a partial one": (
                { try self.createCompleteParakeetModelFolder(at: $0) }, incomplete, true
            ),
            "a duplicate of a complete copy is removed": (
                { try self.createCompleteParakeetModelFolder(at: $0) },
                { try self.createCompleteParakeetModelFolder(at: $0) },
                true
            ),
            "a partial copy is removed": (incomplete, nil, false)
        ]

        for (name, tc) in cases {
            for folder in [legacy, current] where FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            try tc.legacy(legacy)
            try tc.current?(current)

            let manager = ModelManager(settings: settings, cacheBaseURL: cacheBaseURL)
            manager.removeObsoleteDownloads()

            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), name)
            let parakeet = try XCTUnwrap(manager.models.first { $0.id == AppMode.parakeetModelId }, name)
            XCTAssertEqual(parakeet.isDownloaded, tc.wantCurrentComplete, name)
        }
    }

    func testMigrateLegacyUnavailableModelIds() {
        settings[.selectedModel] = "small"
        let migration = modelManager.migrateSelectedModelIfNeeded()
        XCTAssertNotNil(migration)
        XCTAssertEqual(migration?.from, "small")
        XCTAssertEqual(migration?.to, AppMode.parakeetModelId)
        XCTAssertEqual(settings[.selectedModel], "small")
        XCTAssertEqual(modelManager.lastMigration?.from, "small")

        settings[.selectedModel] = "large-v3"
        let migration2 = modelManager.migrateSelectedModelIfNeeded()
        XCTAssertNotNil(migration2)
        XCTAssertEqual(migration2?.from, "large-v3")
        XCTAssertEqual(migration2?.to, AppMode.parakeetModelId)
        XCTAssertEqual(settings[.selectedModel], "large-v3")
        XCTAssertEqual(modelManager.lastMigration?.from, "large-v3")
    }

    func testMigrateRemovedQwenModelIdsToParakeet() {
        for modelId in ["qwen3", "qwen3-0.6b-4bit", "qwen3-0.6b-8bit", "qwen3-1.7b-4bit"] {
            settings[.selectedModel] = modelId
            let migration = modelManager.migrateSelectedModelIfNeeded()
            XCTAssertEqual(migration?.to, AppMode.parakeetModelId, modelId)
            XCTAssertEqual(settings[.selectedModel], modelId)
        }
    }

    func testMigrateRemovedModelsToTheirReplacements() {
        let cases: [String: (from: String, want: String)] = [
            "parakeet v3 becomes ultra": ("parakeet-tdt-v3", AppMode.parakeetMultilingualModelId),
            "nemotron becomes parakeet unified": ("nemotron", AppMode.parakeetUnifiedModelId)
        ]

        for (name, tc) in cases {
            settings[.selectedModel] = tc.from
            let migration = modelManager.migrateSelectedModelIfNeeded()
            XCTAssertEqual(migration?.to, tc.want, name)
            XCTAssertEqual(settings[.selectedModel], tc.from, "\(name): the replacement still needs a download")
        }
    }

    func testDownloadsOfRemovedModelsAreDeletedAtLaunch() throws {
        let removed = ["parakeet-tdt-0.6b-v3", "parakeet-tdt-0.6b-v3-coreml"].map(fluidAudioFolder) + [
            cacheBaseURL.appendingPathComponent("models/aufklarer/Nemotron-Speech-Streaming-0.6B-CoreML-INT8"),
            cacheBaseURL.appendingPathComponent("aufklarer_Nemotron-Speech-Streaming-0.6B-CoreML-INT8")
        ]
        for folder in removed {
            try createCompleteParakeetModelFolder(
                at: folder,
                layout: ModelInstallationValidator.parakeetMultilingualLayout
            )
        }
        let kept = fluidAudioFolder("parakeet-tdt-0.6b-v2")
        try createCompleteParakeetModelFolder(at: kept)

        ModelManager(settings: settings, cacheBaseURL: cacheBaseURL).removeObsoleteDownloads()

        for folder in removed {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), folder.lastPathComponent)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    func testCreatingAManagerLeavesOldDownloadsAlone() throws {
        // Tests and views build ModelManagers freely, some against the real
        // cache, so only the explicit launch step may move or delete files.
        let legacy = fluidAudioFolder("parakeet-tdt-0.6b-v2-coreml")
        let removed = fluidAudioFolder("parakeet-tdt-0.6b-v3")
        try createCompleteParakeetModelFolder(at: legacy)
        try createCompleteParakeetModelFolder(at: removed, layout: ModelInstallationValidator.parakeetMultilingualLayout)

        _ = ModelManager(settings: settings, cacheBaseURL: cacheBaseURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: removed.path))
    }

    func testMigrateExperimentalQwenModelIds() {
        settings[.selectedModel] = "qwen3-asr-0.6b-mlx-4bit"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], "qwen3-asr-0.6b-mlx-4bit")

        settings[.selectedModel] = "qwen3-asr-0.6b-mlx-8bit"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], "qwen3-asr-0.6b-mlx-8bit")

        settings[.selectedModel] = "qwen3-asr-1.7b-mlx-4bit"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], "qwen3-asr-1.7b-mlx-4bit")

        settings[.selectedModel] = "qwen3-asr-1.7b-mlx-8bit"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], "qwen3-asr-1.7b-mlx-8bit")
    }

    func testValidAndUnknownSelectedModelMigration() {
        settings[.selectedModel] = AppMode.parakeetUnifiedModelId
        XCTAssertNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], AppMode.parakeetUnifiedModelId)

        settings[.selectedModel] = "parakeet"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], "parakeet")

        settings[.selectedModel] = "totally-unknown-model"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(settings[.selectedModel], "totally-unknown-model")
    }

    func testLastMigrationNilWhenNoMigrationHappened() {
        settings[.selectedModel] = AppMode.parakeetUnifiedModelId
        XCTAssertNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertNil(modelManager.lastMigration)
    }

    func testLastMigrationNotClearedBySubsequentNoOp() {
        settings[.selectedModel] = "small"
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(modelManager.lastMigration?.from, "small")

        // The pending selection stays unchanged until user action, so a
        // follow-up call reports the same migration without erasing the
        // launch-time migration signal.
        XCTAssertNotNil(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(modelManager.lastMigration?.from, "small")
    }

    func testModelPropertiesAreSet() {
        guard let parakeetModel = modelManager.models.first(where: { $0.id == AppMode.parakeetModelId }) else {
            XCTFail("Parakeet model not found")
            return
        }

        XCTAssertEqual(parakeetModel.name, "Parakeet TDT v2")
        XCTAssertEqual(parakeetModel.description, "NVIDIA Parakeet TDT v2 — fast, accurate English transcription")
        XCTAssertEqual(parakeetModel.sizeHint, "~443MB")
    }

    func testBuiltInModelAlwaysDownloaded() {
        guard let appleModel = modelManager.models.first(where: { $0.id == "apple-speech" }) else {
            XCTFail("Apple Speech model not found")
            return
        }
        XCTAssertTrue(appleModel.isDownloaded, "Built-in model should always be downloaded")
    }

    func testSelectModelReturnsFalseForNonExistentModel() {
        let result = modelManager.selectModel("nonexistent")
        XCTAssertFalse(result, "Should not select non-existent model")
    }

    func testStartDownloadReturnsFalseForNonExistentModel() {
        let result = modelManager.startDownload("nonexistent")
        XCTAssertFalse(result, "Should not start download for non-existent model")
    }

    func testCancelDownloadForNonExistentModelDoesNotCrash() {
        modelManager.cancelDownload("nonexistent")
    }

    func testAcceptedDownloadProgressRequiresActiveDownload() {
        XCTAssertNil(
            ModelManager.acceptedDownloadProgress(
                hasActiveDownload: false,
                isDownloading: true,
                currentProgress: 0.95,
                incomingProgress: 0.97
            )
        )
    }

    func testAcceptedDownloadProgressRequiresDownloadingModel() {
        XCTAssertNil(
            ModelManager.acceptedDownloadProgress(
                hasActiveDownload: true,
                isDownloading: false,
                currentProgress: 1.0,
                incomingProgress: 0.97
            )
        )
    }

    func testAcceptedDownloadProgressDropsBackwardReports() {
        XCTAssertNil(
            ModelManager.acceptedDownloadProgress(
                hasActiveDownload: true,
                isDownloading: true,
                currentProgress: 0.98,
                incomingProgress: 0.97
            )
        )
    }

    func testAcceptedDownloadProgressClampsForwardReports() throws {
        let progress = try XCTUnwrap(
            ModelManager.acceptedDownloadProgress(
                hasActiveDownload: true,
                isDownloading: true,
                currentProgress: 0.98,
                incomingProgress: 1.2
            )
        )
        XCTAssertEqual(progress, 1.0)
    }

    // MARK: - Failed-download folder cleanup

    // The live download path can't be simulated without injecting a downloader
    // seam (ModelHub and HuggingFaceDownloader do real network I/O with
    // retries). That would be invasive refactoring, explicitly out of scope.
    // Instead these tests pin down the destructive helper's path resolution +
    // safety guards, which is where regressions (e.g. deleting the parent
    // models dir) would bite.

    func testRemoveFailedDownloadFolderDeletesOnlyTargetModel() throws {
        let target = fluidAudioFolder("parakeet-tdt-0.6b-v2")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: target.appendingPathComponent("config.json"))

        // A sibling model folder that must be left untouched.
        let sibling = fluidAudioFolder("parakeet-ultra")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: sibling.appendingPathComponent("config.json"))

        modelManager.removeFailedDownloadFolder(for: AppMode.parakeetModelId)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.path),
            "Target partial folder should be removed after failed cleanup"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sibling.path),
            "Sibling model folders must be preserved"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: cacheBaseURL.path),
            "Cache base must be preserved"
        )
    }

    func testRemoveFailedDownloadFolderSafeForUnknownModel() {
        // Unknown model id -> downloadFolder(for:) throws -> helper logs and
        // returns without touching the cache base.
        modelManager.removeFailedDownloadFolder(for: "totally-unknown-model")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: cacheBaseURL.path),
            "Cache base must be untouched when model id is unknown"
        )
    }

    func testEnsureModelDownloadedReturnsExistingFolder() async throws {
        let modelFolder = fluidAudioFolder("parakeet-tdt-0.6b-v2")
        try createCompleteParakeetModelFolder(at: modelFolder)

        let result = try await modelManager.ensureModelDownloaded(AppMode.parakeetModelId)

        XCTAssertEqual(result.path, modelFolder.path)

        let parakeetModel = try XCTUnwrap(
            modelManager.models.first { $0.id == AppMode.parakeetModelId }
        )
        XCTAssertTrue(parakeetModel.isDownloaded)
        XCTAssertEqual(parakeetModel.downloadProgress, 1.0)
    }

    func testDownloadModelForNonExistentModelThrows() async {
        do {
            _ = try await modelManager.downloadModel("nonexistent")
            XCTFail("Expected modelNotFound error")
        } catch let error as ModelError {
            guard case .modelNotFound(let modelId) = error else {
                XCTFail("Expected modelNotFound error, got \(error)")
                return
            }
            XCTAssertEqual(modelId, "nonexistent")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPendingSelectionAppliesOnlyOnceTheModelIsInstalled() throws {
        XCTAssertFalse(modelManager.applyPendingSelection(), "nothing pending")

        modelManager.selectWhenDownloaded(AppMode.parakeetModelId)
        XCTAssertEqual(modelManager.pendingSelectionModelId, AppMode.parakeetModelId)
        XCTAssertFalse(modelManager.applyPendingSelection(), "not downloaded yet")
        XCTAssertEqual(settings[.selectedModel], AppMode.parakeetUnifiedModelId)
        XCTAssertEqual(modelManager.pendingSelectionModelId, AppMode.parakeetModelId, "still waiting")

        try createCompleteParakeetModelFolder(at: fluidAudioFolder("parakeet-tdt-0.6b-v2"))
        modelManager.refreshModels()

        XCTAssertTrue(modelManager.applyPendingSelection())
        XCTAssertEqual(settings[.selectedModel], AppMode.parakeetModelId)
        XCTAssertNil(modelManager.pendingSelectionModelId)
        XCTAssertFalse(modelManager.applyPendingSelection(), "applied only once")
    }

    func testPendingSelectionIsDroppedByOtherChoices() {
        let cases: [String: (ModelManager) -> Void] = [
            "picking a model explicitly": { _ = $0.selectModel(AppMode.appleSpeechModelId) },
            "cancelling the download": { $0.cancelDownload(AppMode.parakeetModelId) }
        ]

        for (name, drop) in cases {
            modelManager.selectWhenDownloaded(AppMode.parakeetModelId)
            drop(modelManager)
            XCTAssertNil(modelManager.pendingSelectionModelId, name)
        }
    }

    func testPendingSelectionIgnoresUnknownModels() {
        modelManager.selectWhenDownloaded("abed-nadir-v9")
        XCTAssertNil(modelManager.pendingSelectionModelId)
    }

    func testSelectModelReturnsFalseWhenModelNotDownloaded() {
        let undownloadedModel = modelManager.models.first { !$0.isDownloaded }
        guard let modelId = undownloadedModel?.id else { return }

        let result = modelManager.selectModel(modelId)
        XCTAssertFalse(result, "Should not select model that isn't downloaded")
    }

    func testSelectModelReturnsFalseForSameModel() {
        let currentModel = settings[.selectedModel]
        let result = modelManager.selectModel(currentModel)
        XCTAssertFalse(result, "Should return false when selecting same model")
    }

    func testDownloadedModelsPropertyFiltersCorrectly() {
        let downloaded = modelManager.downloadedModels

        for model in downloaded {
            XCTAssertTrue(model.isDownloaded, "All models in downloadedModels should be downloaded")
        }
    }

    func testIsSelectedModelDownloadedIsFalseForMissingSelection() {
        // Setup selects Parakeet Unified with an empty cache: not installed. The old
        // "any model downloaded" check was constant-true because built-in
        // Apple Speech always counts as installed.
        XCTAssertFalse(modelManager.isSelectedModelDownloaded)
    }

    func testIsSelectedModelDownloadedIsTrueForBuiltInSelection() {
        settings[.selectedModel] = AppMode.appleSpeechModelId
        modelManager.refreshModels()
        XCTAssertTrue(modelManager.isSelectedModelDownloaded)
    }

    func testModelDownloadStateEquality() {
        let state1 = ModelDownloadState(
            modelId: AppMode.parakeetModelId,
            progress: 0.5,
            status: "Downloading...",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )

        let state2 = ModelDownloadState(
            modelId: AppMode.parakeetModelId,
            progress: 0.5,
            status: "Downloading...",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )

        XCTAssertEqual(state1, state2, "Equal states should be equal")
    }

    func testModelDownloadStateInequality() {
        let state1 = ModelDownloadState(
            modelId: AppMode.parakeetModelId,
            progress: 0.5,
            status: "Downloading...",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )

        let state2 = ModelDownloadState(
            modelId: AppMode.parakeetUnifiedModelId,
            progress: 0.5,
            status: "Downloading...",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )

        XCTAssertNotEqual(state1, state2, "Different model IDs should not be equal")
    }

    func testModelDownloadStatePhases() {
        let phases: [ModelDownloadState.Phase] = [.started, .progress, .finished, .failed]

        for phase in phases {
            let state = ModelDownloadState(
                modelId: AppMode.parakeetModelId,
                progress: 0.5,
                status: "Test",
                phase: phase,
                errorDescription: nil,
                isCancelled: false
            )
            XCTAssertEqual(state.phase, phase, "Phase should be stored correctly")
        }
    }

    func testModelStructIdentifiable() {
        let models = modelManager.models
        let uniqueIds = Set(models.map { $0.id })
        XCTAssertEqual(uniqueIds.count, models.count, "All model IDs should be unique")
    }

    private func fluidAudioFolder(_ name: String) -> URL {
        cacheBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("FluidInference", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private func createCompleteParakeetModelFolder(
        at url: URL,
        layout: ModelInstallationValidator.FolderLayout = ModelInstallationValidator.parakeetLayout
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        for fileName in layout.files {
            try Data("test".utf8).write(to: url.appendingPathComponent(fileName))
        }
        for directoryName in layout.directories {
            let directory = url.appendingPathComponent(directoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("test".utf8).write(
                to: directory.appendingPathComponent(ModelInstallationValidator.coreMLBundleMarkerFile)
            )
        }
    }
}
