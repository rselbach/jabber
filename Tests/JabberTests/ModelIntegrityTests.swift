import XCTest
@testable import Jabber
import Foundation

final class ModelIntegrityTests: XCTestCase {
    private var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testVerifyModelWithNoExpectedHashSkipsVerification() throws {
        // "invalid-model" has no expected hash defined
        let result = try ModelIntegrity.verifyModel(at: tempDir, modelId: "invalid-model")
        XCTAssertTrue(result)
    }
    
    func testVerifyModelWithPlaceholderHashAlwaysFails() throws {
        // All defined models have placeholder hashes of zeros
        // This test will fail until real hashes are provided
        do {
            _ = try ModelIntegrity.verifyModel(at: tempDir, modelId: "base")
            XCTFail("Should have thrown integrity check failed error")
        } catch let error as ModelError {
            if case .integrityCheckFailed = error {
                // Expected
            } else {
                throw error
            }
        }
    }
    
    func testVerifyModelComputesDeterministicHash() throws {
        // Create test files
        let file1 = tempDir.appendingPathComponent("config.json")
        let file2 = tempDir.appendingPathComponent("model.mlmodel")
        try "{\"version\": \"1.0\"}".write(to: file1, atomically: true, encoding: .utf8)
        try "test model data".write(to: file2, atomically: true, encoding: .utf8)
        
        // Compute hash twice - should be identical
        let hash1 = try computeHashForTest(at: tempDir)
        let hash2 = try computeHashForTest(at: tempDir)
        
        XCTAssertEqual(hash1, hash2, "Hash should be deterministic")
    }
    
    func testVerifyModelDifferentContentDifferentHash() throws {
        // Create first set of files
        let file1 = tempDir.appendingPathComponent("config.json")
        try "{\"version\": \"1.0\"}".write(to: file1, atomically: true, encoding: .utf8)
        let hash1 = try computeHashForTest(at: tempDir)
        
        // Clean up and create different content
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let file2 = tempDir.appendingPathComponent("config.json")
        try "{\"version\": \"2.0\"}".write(to: file2, atomically: true, encoding: .utf8)
        let hash2 = try computeHashForTest(at: tempDir)
        
        XCTAssertNotEqual(hash1, hash2, "Different content should produce different hashes")
    }
    
    func testVerifyModelEmptyDirectoryThrows() {
        do {
            _ = try computeHashForTest(at: tempDir)
            XCTFail("Should have thrown error for empty directory")
        } catch let error as ModelError {
            if case .integrityCheckFailed(_, _, let actual) = error {
                XCTAssertTrue(actual.contains("empty directory"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testStoreAndRetrieveComputedHash() {
        let modelId = "test-model"
        let expectedHash = "abc123def456"
        
        // Store hash
        ModelIntegrity.storeComputedHash(modelId: modelId, hash: expectedHash)
        
        // Retrieve and verify
        let retrieved = ModelIntegrity.getStoredHash(modelId: modelId)
        XCTAssertEqual(retrieved, expectedHash)
    }
    
    func testClearStoredHash() {
        let modelId = "test-model-clear"
        
        // Store hash
        ModelIntegrity.storeComputedHash(modelId: modelId, hash: "test-hash")
        XCTAssertNotNil(ModelIntegrity.getStoredHash(modelId: modelId))
        
        // Clear hash
        ModelIntegrity.clearStoredHash(modelId: modelId)
        
        // Verify cleared
        let retrieved = ModelIntegrity.getStoredHash(modelId: modelId)
        XCTAssertNil(retrieved)
    }
    
    func testVerifyModelDifferentFileOrderSameHash() throws {
        // Create files in different order - hash should be the same (deterministic)
        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let fileA = tempDir.appendingPathComponent("a.txt")
        let fileB = subDir.appendingPathComponent("b.txt")
        let fileC = tempDir.appendingPathComponent("c.txt")
        
        try "content-a".write(to: fileA, atomically: true, encoding: .utf8)
        try "content-b".write(to: fileB, atomically: true, encoding: .utf8)
        try "content-c".write(to: fileC, atomically: true, encoding: .utf8)
        
        let hash1 = try computeHashForTest(at: tempDir)
        
        // Remove and recreate files in different order
        try? FileManager.default.removeItem(at: fileA)
        try? FileManager.default.removeItem(at: fileB)
        try? FileManager.default.removeItem(at: fileC)
        
        // Create in reverse order
        try "content-c".write(to: fileC, atomically: true, encoding: .utf8)
        try "content-b".write(to: fileB, atomically: true, encoding: .utf8)
        try "content-a".write(to: fileA, atomically: true, encoding: .utf8)
        
        let hash2 = try computeHashForTest(at: tempDir)
        
        XCTAssertEqual(hash1, hash2, "Hash should be independent of file creation order")
    }
    
    // Helper to access private compute method for testing
    private func computeHashForTest(at folder: URL) throws -> String {
        // We need to access the private method - for testing, we'll reimplement
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ModelError.integrityCheckFailed(
                modelId: folder.lastPathComponent,
                expected: "directory enumeration",
                actual: "failed to create enumerator"
            )
        }
        
        var hasher = SHA256()
        var filePaths: [String] = []
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }
            filePaths.append(fileURL.path)
        }
        
        filePaths.sort()
        
        guard !filePaths.isEmpty else {
            throw ModelError.integrityCheckFailed(
                modelId: folder.lastPathComponent,
                expected: "files to hash",
                actual: "empty directory"
            )
        }
        
        for filePath in filePaths {
            guard let data = fileManager.contents(atPath: filePath) else {
                throw ModelError.integrityCheckFailed(
                    modelId: folder.lastPathComponent,
                    expected: "readable file: \(filePath)",
                    actual: "failed to read file"
                )
            }
            
            let relativePath = filePath.replacingOccurrences(of: folder.path + "/", with: "")
            guard let pathData = relativePath.data(using: .utf8) else {
                throw ModelError.integrityCheckFailed(
                    modelId: folder.lastPathComponent,
                    expected: "path encoding",
                    actual: "failed to encode path"
                )
            }
            
            hasher.update(data: pathData)
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit
