import XCTest
@testable import Jabber

@MainActor
final class ModelManagerTests: XCTestCase {
    private var modelManager: ModelManager!
    
    override func setUp() {
        super.setUp()
        modelManager = ModelManager.shared
        TypedSettings[.selectedModel] = AppMode.baseModelId
    }

    override func tearDown() {
        TypedSettings[.selectedModel] = AppMode.baseModelId
        super.tearDown()
    }
    
    func testModelDefinitionsExist() {
        XCTAssertFalse(modelManager.models.isEmpty, "Should have model definitions")
        
        // Verify known models exist
        let modelIds = modelManager.models.map { $0.id }
        XCTAssertTrue(modelIds.contains("base"), "Should have base model")
        XCTAssertTrue(modelIds.contains("medium"), "Should have medium model")
        XCTAssertTrue(modelIds.contains("large"), "Should have large model")
        XCTAssertEqual(modelIds.count, 3, "Should only expose the three Qwen3-ASR models")
    }

    func testQwen3ASRVariantsResolveHuggingFaceIds() {
        XCTAssertEqual(
            ModelManager.qwen3ASRHuggingFaceModelId(for: AppMode.baseModelId),
            "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        )
        XCTAssertEqual(
            ModelManager.qwen3ASRHuggingFaceModelId(for: AppMode.mediumModelId),
            "mlx-community/Qwen3-ASR-1.7B-4bit"
        )
        XCTAssertEqual(
            ModelManager.qwen3ASRHuggingFaceModelId(for: AppMode.largeModelId),
            "aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
        )
        XCTAssertNil(ModelManager.qwen3ASRHuggingFaceModelId(for: "tiny"))
    }

    func testMigrateLegacyUnavailableModelIds() {
        TypedSettings[.selectedModel] = "small"
        XCTAssertTrue(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.baseModelId)

        TypedSettings[.selectedModel] = "large-v3"
        XCTAssertTrue(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.largeModelId)
    }

    func testMigrateExperimentalQwenModelIds() {
        TypedSettings[.selectedModel] = "qwen3-asr-0.6b-mlx-4bit"
        XCTAssertTrue(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.baseModelId)

        TypedSettings[.selectedModel] = "qwen3-asr-1.7b-mlx-4bit"
        XCTAssertTrue(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.mediumModelId)

        TypedSettings[.selectedModel] = "qwen3-asr-1.7b-mlx-8bit"
        XCTAssertTrue(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.largeModelId)
    }

    func testValidAndUnknownSelectedModelMigration() {
        TypedSettings[.selectedModel] = AppMode.mediumModelId
        XCTAssertFalse(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.mediumModelId)

        TypedSettings[.selectedModel] = "totally-unknown-model"
        XCTAssertTrue(modelManager.migrateSelectedModelIfNeeded())
        XCTAssertEqual(TypedSettings[.selectedModel], AppMode.baseModelId)
    }
    
    func testModelPropertiesAreSet() {
        guard let baseModel = modelManager.models.first(where: { $0.id == "base" }) else {
            XCTFail("Base model not found")
            return
        }
        
        XCTAssertEqual(baseModel.name, "Base")
        XCTAssertEqual(baseModel.description, "Fast, accurate Qwen3-ASR 0.6B 4-bit")
        XCTAssertEqual(baseModel.sizeHint, "~700MB")
    }
    
    func testSelectModelReturnsFalseForNonExistentModel() {
        let result = modelManager.selectModel("nonexistent", previousModelId: nil)
        XCTAssertFalse(result, "Should not select non-existent model")
    }

    func testStartDownloadReturnsFalseForNonExistentModel() {
        let result = modelManager.startDownload("nonexistent")
        XCTAssertFalse(result, "Should not start download for non-existent model")
    }

    func testCancelDownloadForNonExistentModelDoesNotCrash() {
        modelManager.cancelDownload("nonexistent")
    }
    
    func testSelectModelReturnsFalseWhenModelNotDownloaded() {
        // Find a model that isn't downloaded
        let undownloadedModel = modelManager.models.first { !$0.isDownloaded }
        guard let modelId = undownloadedModel?.id else {
            // All models are downloaded, skip this test
            return
        }
        
        let result = modelManager.selectModel(modelId, previousModelId: nil)
        XCTAssertFalse(result, "Should not select model that isn't downloaded")
    }
    
    func testSelectModelReturnsFalseForSameModel() {
        // Get currently selected model
        let currentModel = TypedSettings[.selectedModel]
        let result = modelManager.selectModel(currentModel, previousModelId: currentModel)
        XCTAssertFalse(result, "Should return false when selecting same model")
    }
    
    func testDownloadedModelsPropertyFiltersCorrectly() {
        let downloaded = modelManager.downloadedModels
        
        for model in downloaded {
            XCTAssertTrue(model.isDownloaded, "All models in downloadedModels should be downloaded")
        }
    }
    
    func testHasAnyDownloadedModelReflectsState() {
        let hasDownloaded = modelManager.hasAnyDownloadedModel
        let expected = !modelManager.downloadedModels.isEmpty
        XCTAssertEqual(hasDownloaded, expected, "hasAnyDownloadedModel should reflect downloadedModels state")
    }
    
    func testModelDownloadStateEquality() {
        let state1 = ModelDownloadState(
            modelId: "base",
            progress: 0.5,
            status: "Downloading...",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )
        
        let state2 = ModelDownloadState(
            modelId: "base",
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
            modelId: "base",
            progress: 0.5,
            status: "Downloading...",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )
        
        let state2 = ModelDownloadState(
            modelId: "large",
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
                modelId: "base",
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
}
