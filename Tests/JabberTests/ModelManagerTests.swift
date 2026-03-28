import XCTest
@testable import Jabber

@MainActor
final class ModelManagerTests: XCTestCase {
    private var modelManager: ModelManager!
    
    override func setUp() {
        super.setUp()
        modelManager = ModelManager.shared
    }
    
    func testModelDefinitionsExist() {
        XCTAssertFalse(modelManager.models.isEmpty, "Should have model definitions")
        
        // Verify known models exist
        let modelIds = modelManager.models.map { $0.id }
        XCTAssertTrue(modelIds.contains("tiny"), "Should have tiny model")
        XCTAssertTrue(modelIds.contains("base"), "Should have base model")
        XCTAssertTrue(modelIds.contains("small"), "Should have small model")
        XCTAssertTrue(modelIds.contains("medium"), "Should have medium model")
        XCTAssertTrue(modelIds.contains("large-v3"), "Should have large-v3 model")
    }
    
    func testModelPropertiesAreSet() {
        guard let baseModel = modelManager.models.first(where: { $0.id == "base" }) else {
            XCTFail("Base model not found")
            return
        }
        
        XCTAssertEqual(baseModel.name, "Base")
        XCTAssertEqual(baseModel.description, "Balanced speed/accuracy")
        XCTAssertEqual(baseModel.sizeHint, "~140MB")
    }
    
    func testSelectModelReturnsFalseForNonExistentModel() {
        let result = modelManager.selectModel("nonexistent", previousModelId: nil)
        XCTAssertFalse(result, "Should not select non-existent model")
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
        let currentModel = AppSettings.string(AppSettingKey.selectedModel, default: AppMode.baseModelId)
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
            modelId: "tiny",
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
