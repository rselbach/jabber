import XCTest
@testable import Jabber

final class ModelInstallationValidatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JabberTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testCompleteParakeetFolderIsValid() throws {
        try writeFile(named: "parakeet_vocab.json")
        for directory in ModelInstallationValidator.parakeetLayout.directories {
            try createCoreMLBundle(named: directory)
        }

        let validation = ModelInstallationValidator.validateParakeetModelFolder(at: tempDir)

        XCTAssertTrue(validation.isComplete)
        XCTAssertEqual(validation.missingRequiredFiles, [])
        XCTAssertTrue(validation.hasWeights)
    }

    func testMissingParakeetVocabularyIsInvalid() throws {
        for directory in ModelInstallationValidator.parakeetLayout.directories {
            try createCoreMLBundle(named: directory)
        }

        let validation = ModelInstallationValidator.validateParakeetModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertEqual(validation.missingRequiredFiles, ["parakeet_vocab.json"])
    }

    func testEmptyParakeetBundleIsInvalid() throws {
        try writeFile(named: "parakeet_vocab.json")
        for directory in ModelInstallationValidator.parakeetLayout.directories {
            try createCoreMLBundle(named: directory)
        }
        let emptyBundle = tempDir.appendingPathComponent("Encoder.mlmodelc")
        try FileManager.default.removeItem(at: emptyBundle)
        try FileManager.default.createDirectory(at: emptyBundle, withIntermediateDirectories: true)

        let validation = ModelInstallationValidator.validateParakeetModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.hasWeights)
    }

    func testMissingParakeetFolderIsInvalid() {
        let missingFolder = tempDir.appendingPathComponent("missing", isDirectory: true)

        let validation = ModelInstallationValidator.validateParakeetModelFolder(at: missingFolder)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.folderExists)
        XCTAssertEqual(
            validation.missingRequiredFiles,
            ModelInstallationValidator.parakeetLayout.requiredAssets
        )
    }

    func testMultilingualParakeetNeedsItsOwnJointBundle() throws {
        try writeFile(named: "parakeet_vocab.json")
        try createCoreMLBundle(named: "Preprocessor.mlmodelc")
        try createCoreMLBundle(named: "Encoder.mlmodelc")
        try createCoreMLBundle(named: "Decoder.mlmodelc")
        // The v2 joint graph, which v3 cannot use.
        try createCoreMLBundle(named: "JointDecision.mlmodelc")

        let layout = ModelInstallationValidator.parakeetLayout(for: AppMode.parakeetMultilingualModelId)
        let validation = ModelInstallationValidator.validateParakeetModelFolder(at: tempDir, layout: layout)

        XCTAssertFalse(validation.isComplete)
        XCTAssertEqual(validation.missingRequiredFiles, ["JointDecisionv3.mlmodelc"])

        try createCoreMLBundle(named: "JointDecisionv3.mlmodelc")
        let revalidated = ModelInstallationValidator.validateParakeetModelFolder(at: tempDir, layout: layout)
        XCTAssertTrue(revalidated.isComplete)
    }

    func testParakeetLayoutIsSelectedByModelId() {
        XCTAssertEqual(
            ModelInstallationValidator.parakeetLayout(for: AppMode.parakeetModelId),
            ModelInstallationValidator.parakeetLayout
        )
        XCTAssertEqual(
            ModelInstallationValidator.parakeetLayout(for: AppMode.parakeetMultilingualModelId),
            ModelInstallationValidator.parakeetMultilingualLayout
        )
    }

    func testCompleteCoreMLTransducerFolderIsValid() throws {
        try writeFile(named: "config.json")
        try writeFile(named: "vocab.json")
        try createCoreMLBundle(named: "encoder.mlmodelc")
        try createCoreMLBundle(named: "decoder.mlmodelc")
        try createCoreMLBundle(named: "joint.mlmodelc")

        let validation = ModelInstallationValidator.validateCoreMLTransducerModelFolder(at: tempDir)

        XCTAssertTrue(validation.isComplete)
        XCTAssertTrue(validation.hasWeights)
    }

    func testMissingCoreMLTransducerBundleIsInvalid() throws {
        try writeFile(named: "config.json")
        try writeFile(named: "vocab.json")
        try createCoreMLBundle(named: "encoder.mlmodelc")
        try createCoreMLBundle(named: "decoder.mlmodelc")

        let validation = ModelInstallationValidator.validateCoreMLTransducerModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.hasWeights)
        XCTAssertTrue(validation.missingRequiredFiles.contains("joint.mlmodelc"))
    }

    private func writeFile(named name: String) throws {
        try Data("Greendale Community College".utf8).write(to: tempDir.appendingPathComponent(name))
    }

    private func createCoreMLBundle(named name: String) throws {
        let bundle = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("Human Being mascot".utf8).write(
            to: bundle.appendingPathComponent(ModelInstallationValidator.coreMLBundleMarkerFile)
        )
    }
}
