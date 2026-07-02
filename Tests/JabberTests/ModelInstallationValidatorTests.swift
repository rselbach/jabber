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

    func testCompleteQwen3ASRFolderIsValid() throws {
        try writeRequiredModelFiles()
        try writeFile(named: "model.safetensors")

        let validation = ModelInstallationValidator.validateQwen3ASRModelFolder(at: tempDir)

        XCTAssertTrue(validation.isComplete)
        XCTAssertEqual(validation.missingRequiredFiles, [])
        XCTAssertTrue(validation.hasWeights)
        XCTAssertNil(validation.readErrorDescription)
    }

    func testMissingTokenizerFileIsInvalid() throws {
        try writeRequiredModelFiles(except: "tokenizer_config.json")
        try writeFile(named: "model.safetensors")

        let validation = ModelInstallationValidator.validateQwen3ASRModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertEqual(validation.missingRequiredFiles, ["tokenizer_config.json"])
        XCTAssertTrue(validation.hasWeights)
        XCTAssertTrue(validation.failureDescription.contains("tokenizer_config.json"))
    }

    func testMissingSafetensorsWeightsIsInvalid() throws {
        try writeRequiredModelFiles()

        let validation = ModelInstallationValidator.validateQwen3ASRModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertEqual(validation.missingRequiredFiles, [])
        XCTAssertFalse(validation.hasWeights)
        XCTAssertTrue(validation.failureDescription.contains("missing model weights"))
    }

    func testMissingFolderIsInvalid() {
        let missingFolder = tempDir.appendingPathComponent("missing", isDirectory: true)

        let validation = ModelInstallationValidator.validateQwen3ASRModelFolder(at: missingFolder)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.folderExists)
        XCTAssertEqual(
            validation.missingRequiredFiles,
            ModelInstallationValidator.requiredQwen3ASRFiles
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

    func testMissingMlmodelcDirectoryIsInvalid() throws {
        try writeFile(named: "config.json")
        try writeFile(named: "vocab.json")
        try createCoreMLBundle(named: "encoder.mlmodelc")
        try createCoreMLBundle(named: "decoder.mlmodelc")

        let validation = ModelInstallationValidator.validateCoreMLTransducerModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.hasWeights)
        XCTAssertTrue(validation.missingRequiredFiles.contains("joint.mlmodelc"))
    }

    func testEmptyMlmodelcBundlesAreInvalid() throws {
        try writeFile(named: "config.json")
        try writeFile(named: "vocab.json")
        try createDirectory(named: "encoder.mlmodelc")
        try createDirectory(named: "decoder.mlmodelc")
        try createDirectory(named: "joint.mlmodelc")

        let validation = ModelInstallationValidator.validateCoreMLTransducerModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.hasWeights)
    }

    func testPartiallyPopulatedMlmodelcBundleIsInvalid() throws {
        try writeFile(named: "config.json")
        try writeFile(named: "vocab.json")
        try createCoreMLBundle(named: "encoder.mlmodelc")
        try createDirectory(named: "decoder.mlmodelc")
        try createCoreMLBundle(named: "joint.mlmodelc")

        let validation = ModelInstallationValidator.validateCoreMLTransducerModelFolder(at: tempDir)

        XCTAssertFalse(validation.isComplete)
        XCTAssertFalse(validation.hasWeights)
    }

    private func writeRequiredModelFiles(except excludedFile: String? = nil) throws {
        for file in ModelInstallationValidator.requiredQwen3ASRFiles where file != excludedFile {
            try writeFile(named: file)
        }
    }

    private func writeFile(named name: String) throws {
        let data = Data("Greendale Community College".utf8)
        try data.write(to: tempDir.appendingPathComponent(name))
    }

    private func createDirectory(named name: String) throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(name),
            withIntermediateDirectories: true
        )
    }

    private func createCoreMLBundle(named name: String) throws {
        let bundle = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let data = Data("Human Being mascot".utf8)
        try data.write(
            to: bundle.appendingPathComponent(ModelInstallationValidator.coreMLBundleMarkerFile)
        )
    }
}
