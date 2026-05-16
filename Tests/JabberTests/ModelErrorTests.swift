import XCTest
@testable import Jabber

final class ModelErrorTests: XCTestCase {
    func testCannotDeleteActiveModelErrorDescription() {
        let error = ModelError.cannotDeleteActiveModel
        XCTAssertEqual(error.errorDescription, "Cannot delete the currently active model. Please select a different model first.")
    }
    
    func testDownloadTimeoutErrorDescription() {
        let error = ModelError.downloadTimeout(modelId: "base")
        XCTAssertEqual(error.errorDescription, "Download timed out for model 'base'.")
    }
    
    func testModelNotFoundErrorDescription() {
        let error = ModelError.modelNotFound(modelId: "nonexistent")
        XCTAssertEqual(error.errorDescription, "Model 'nonexistent' not found or already deleted.")
    }
}
