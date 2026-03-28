import CryptoKit
import Foundation
import os

/// Manages integrity verification for downloaded Whisper models.
/// Uses SHA-256 hashing to verify model files haven't been tampered with.
enum ModelIntegrity {
    private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "ModelIntegrity")

    /// Expected SHA-256 hashes for each model variant.
    /// These are calculated from the official WhisperKit CoreML models.
    /// IMPORTANT: Update these when WhisperKit releases new model versions.
    static let expectedHashes: [String: String] = [
        // NOTE: These are placeholder hashes. Calculate actual hashes from official models
        // using: find <model-dir> -type f -exec sha256sum {} \; | sort | sha256sum
        "tiny": "0000000000000000000000000000000000000000000000000000000000000000",
        "base": "0000000000000000000000000000000000000000000000000000000000000000",
        "small": "0000000000000000000000000000000000000000000000000000000000000000",
        "medium": "0000000000000000000000000000000000000000000000000000000000000000",
        "large-v3": "0000000000000000000000000000000000000000000000000000000000000000",
    ]

    /// Verifies the integrity of a downloaded model directory.
    /// - Parameter modelFolder: URL to the model directory
    /// - Parameter modelId: The model identifier (e.g., "base", "tiny")
    /// - Returns: True if the model passes integrity verification
    /// - Throws: ModelError.integrityCheckFailed if verification fails
    static func verifyModel(at modelFolder: URL, modelId: String) throws -> Bool {
        guard let expectedHash = expectedHashes[modelId] else {
            logger.warning("No expected hash defined for model '\(modelId)', skipping verification")
            return true
        }

        let computedHash = try computeHash(for: modelFolder)

        guard computedHash.lowercased() == expectedHash.lowercased() else {
            logger.error("Model integrity check failed for '\(modelId)': expected \(expectedHash), got \(computedHash)")
            throw ModelError.integrityCheckFailed(
                modelId: modelId,
                expected: expectedHash,
                actual: computedHash
            )
        }

        logger.info("Model '\(modelId)' passed integrity verification")
        return true
    }

    /// Computes a SHA-256 hash of all files in a directory.
    /// Hashes are computed in a deterministic order (sorted by filename).
    /// - Parameter folder: URL to the directory
    /// - Returns: Hex-encoded SHA-256 hash string
    /// - Throws: ModelError if file reading fails
    private static func computeHash(for folder: URL) throws -> String {
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

        // Collect all file paths
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }
            filePaths.append(fileURL.path)
        }

        // Sort for deterministic hashing
        filePaths.sort()

        guard !filePaths.isEmpty else {
            throw ModelError.integrityCheckFailed(
                modelId: folder.lastPathComponent,
                expected: "files to hash",
                actual: "empty directory"
            )
        }

        // Hash each file
        for filePath in filePaths {
            guard let data = fileManager.contents(atPath: filePath) else {
                throw ModelError.integrityCheckFailed(
                    modelId: folder.lastPathComponent,
                    expected: "readable file: \(filePath)",
                    actual: "failed to read file"
                )
            }

            // Include relative path in hash for structure verification
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

    /// Stores the computed hash for a model after successful download.
    /// This allows future verification without hardcoded hashes.
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - hash: The computed hash
    static func storeComputedHash(modelId: String, hash: String) {
        let key = "model_computed_hash_\(modelId)"
        UserDefaults.standard.set(hash, forKey: key)
        logger.info("Stored computed hash for '\(modelId)'")
    }

    /// Retrieves the stored hash for a model.
    /// - Parameter modelId: The model identifier
    /// - Returns: The stored hash, or nil if not found
    static func getStoredHash(modelId: String) -> String? {
        let key = "model_computed_hash_\(modelId)"
        return UserDefaults.standard.string(forKey: key)
    }

    /// Clears the stored hash for a model.
    /// Called when a model is deleted.
    /// - Parameter modelId: The model identifier
    static func clearStoredHash(modelId: String) {
        let key = "model_computed_hash_\(modelId)"
        UserDefaults.standard.removeObject(forKey: key)
    }
}
